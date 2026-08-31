# frozen_string_literal: true

require "coverage"
require_relative "production/error"

#
# Production coverage mode (#1271). Deliberately loadable on its own:
# `require "simplecov/production"` pulls in none of the reporting machinery,
# because a production process wants a measurement tap and nothing else.
# Nothing here runs unless `SimpleCov::Production.start` is called explicitly.
#
module SimpleCov
  module Production
    class << self
      # Answers false, with a warning naming why, when it safely declines
      # (already running, another Coverage owner such as a test suite, or a
      # runtime without oneshot lines). Configuration mistakes raise `Error`
      # instead: a typo'd interval should fail deployment, not quietly measure
      # wrong.
      #
      # In a forking server, call this from the worker-boot hook (Puma's
      # `on_worker_boot`, Unicorn's `after_fork`): the flush thread does not
      # survive a fork, and `start` in the child picks the inherited
      # measurement back up.
      def start(root: Dir.pwd, sink: nil, flush_interval: 60, flush_jitter: nil, sample_rate: 1.0,
                max_buffered_lines: 1_000_000)
        validate!(flush_interval, flush_jitter, sample_rate, max_buffered_lines)
        return warn_decline("SimpleCov::Production is already running") if running?
        return false unless claim_coverage

        configure(root, sink, flush_interval: flush_interval, flush_jitter: flush_jitter,
                              sample_rate: sample_rate, max_buffered_lines: max_buffered_lines)
        @running = true
        @pid = Process.pid
        install_at_exit
        spawn_flush_thread
        true
      end

      # Both are small Integers, so identity settles it: a measurement belongs to
      # the process that started it and to no other.
      def running?
        !!@running && @pid.equal?(Process.pid)
      end

      # Called by the flush thread every interval; public so a deploy hook (or a
      # signal handler) can force one. An empty delta counts as accepted.
      def flush
        return false unless running?

        @mutex.synchronize do
          pull_pending
          push_pending
        end
      end

      def stop
        return false unless running?

        @running = false
        wake_flush_thread
        @thread&.join
        @mutex.synchronize do
          pull_pending
          push_pending
          Coverage.result(stop: true, clear: true)
        end
        true
      end

      # @api private -- clears module state between tests. The at_exit
      # registration flag survives on purpose: one hook per process.
      def reset!
        @running = false
        wake_flush_thread if @thread
        @thread&.join
        @thread = nil
        @pending = {}
        @pid = nil
        @started_coverage = false
      end

    private

      def validate!(flush_interval, flush_jitter, sample_rate, max_buffered_lines)
        raise Error, "flush_interval must be a positive number of seconds" unless flush_interval.positive?

        validate_jitter!(flush_jitter)
        raise Error, "sample_rate must be within (0, 1]" unless sample_rate.positive? && sample_rate <= 1
        raise Error, "max_buffered_lines must be positive" unless max_buffered_lines.positive?
        return unless sample_rate < 1 && !Coverage.respond_to?(:suspend)

        raise Error, "sample_rate below 1.0 needs Coverage.suspend (Ruby 3.2 or later)"
      end

      def validate_jitter!(flush_jitter)
        return if flush_jitter.nil? || (flush_jitter.is_a?(Numeric) && flush_jitter >= 0)

        raise Error, "flush_jitter must be a non-negative number of seconds"
      end

      # A running Coverage belongs to someone else, unless this very module
      # started it before a fork, in which case the child inherits the
      # measurement and only needs its own flush thread.
      def claim_coverage
        if Coverage.running?
          return true if @started_coverage && @pid && !@pid.equal?(Process.pid)

          return warn_decline("Coverage is already running (a test suite or another tool owns it)")
        end
        return warn_decline("this runtime has no oneshot lines support") unless oneshot_supported?

        Coverage.start(oneshot_lines: true)
        @started_coverage = true
      end

      def oneshot_supported?
        !Coverage.respond_to?(:supported?) || Coverage.supported?(:oneshot_lines)
      end

      def configure(root, sink, flush_interval:, flush_jitter:, sample_rate:, max_buffered_lines:)
        @root_prefix = File.expand_path(root) + File::SEPARATOR
        @sink = sink || default_sink(root)
        @flush_interval = flush_interval
        @flush_jitter = flush_jitter || (flush_interval / 10.0)
        @sample_rate = sample_rate
        @max_buffered_lines = max_buffered_lines
        @pending = {} #: Hash[String, Set[Integer]]
        @measuring = true
        @mutex = Mutex.new
        @waiter = ConditionVariable.new
      end

      def default_sink(root)
        FileSink.new(path: File.join(root, "tmp", "simplecov", "production.json"))
      end

      def spawn_flush_thread
        thread = Thread.new { flush_loop }
        thread.name = "SimpleCov::Production flusher"
        @thread = thread
      end

      # The condition variable rather than a bare sleep is what lets `stop`
      # return promptly instead of waiting out a long interval.
      def flush_loop
        @mutex.synchronize do
          while @running
            @waiter.wait(@mutex, next_wait)
            cycle if @running
          end
        end
      end

      # A fresh random share of the jitter per wait: a fleet of workers booted
      # together would otherwise contend on the shared sink at the same instant
      # every interval, forever.
      def next_wait
        @flush_interval + (rand * @flush_jitter)
      end

      def wake_flush_thread
        @mutex.synchronize { @waiter.signal }
      end

      def cycle
        resample
        pull_pending
        push_pending
      end

      # Duty-cycle sampling: with `sample_rate` 0.25, roughly one interval in
      # four measures and the rest are suspended, capping steady-state overhead
      # while every line still gets its chance over time.
      def resample
        return unless @sample_rate < 1

        wanted = rand < @sample_rate
        if wanted && !@measuring
          Coverage.resume
        elsif !wanted && @measuring
          Coverage.suspend
        end
        @measuring = wanted
      end

      # Clearing on read means a line executed again later re-reports, which is
      # what lets a dropped buffer heal for still-hot code.
      def pull_pending
        Coverage.result(stop: false, clear: true).each do |path, data|
          lines = data[:oneshot_lines]
          next if lines.nil? || lines.empty?

          relative = relativize(path)
          next unless relative

          (@pending[relative] ||= Set.new).merge(lines)
        end
      end

      # On failure the buffer is kept for the next interval, bounded by the
      # ceiling so a long outage cannot grow memory without limit.
      def push_pending
        return true if @pending.empty?

        @sink.store(@pending.transform_values(&:sort))
        @pending.clear
        true
      rescue StandardError => e
        warn "[SimpleCov::Production] flush failed (#{e.class}: #{e}); retrying next interval"
        enforce_ceiling
        false
      end

      # Oneshot's re-reporting is what makes dropping safe-ish: lines still being
      # executed report again after the drop, and only code that ran during the
      # outage and never again is lost.
      def enforce_ceiling
        return if @pending.sum { |_path, lines| lines.size } <= @max_buffered_lines

        @pending.clear
        warn "[SimpleCov::Production] buffer ceiling (#{@max_buffered_lines} lines) exceeded " \
             "while the sink was unreachable; dropping buffered coverage"
      end

      def relativize(path)
        return nil unless path.start_with?(@root_prefix)

        path[@root_prefix.length..]
      end

      def warn_decline(reason)
        warn "[SimpleCov::Production] not starting: #{reason}"
        false
      end

      def install_at_exit
        return if @at_exit_installed

        @at_exit_installed = true
        at_exit do
          stop
        end
      end
    end
  end
end

require_relative "production/file_sink"
