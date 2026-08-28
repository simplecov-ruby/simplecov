# frozen_string_literal: true

require "coverage"
require_relative "production/error"

# Production coverage mode (see #1271): measure which lines real traffic
# executes, cheaply enough to leave running, and durably enough to cross
# with the test report later (`simplecov dead-code`).
#
# This file is deliberately loadable on its own — `require
# "simplecov/production"` pulls in none of the reporting machinery, no
# formatters, and no at_exit report, because a production process wants
# a measurement tap and nothing else. Nothing here runs unless
# `SimpleCov::Production.start` is called explicitly.
#
# The measurement is `:oneshot_lines` coverage: each line reports its
# first execution and nothing after, which is what makes the overhead
# viable in production. On every flush interval a background thread
# drains the runtime's oneshot table (clearing it, so a line hit again
# later re-reports) and hands root-relative line numbers to a sink,
# which merges them into shared storage. A plain locking file sink ships
# in the box; anything with a `store(coverage)` method — Redis, S3, a
# metrics pipeline — can stand in, living outside this gem.
module SimpleCov
  # See the file-top comment. One cohesive runtime state machine; kept
  # in one class for the same reason a state machine is not split
  # across files by size alone.
  # rubocop:disable Metrics/ModuleLength, Metrics/ClassLength
  module Production
    class << self
      # Begin measuring. Returns true when measurement started, false —
      # with a warning naming why — when it safely declined (already
      # running, another Coverage owner such as a test suite, or a
      # runtime without oneshot lines). Configuration mistakes raise
      # `Error` instead: a typo'd interval should fail deployment, not
      # quietly measure wrong.
      #
      #   SimpleCov::Production.start(
      #     root: Rails.root.to_s,
      #     sink: SimpleCov::Production::FileSink.new(path: "/var/data/coverage/production.json"),
      #     flush_interval: 60,        # seconds between drains
      #     flush_jitter: 6,           # extra random wait per drain (default a tenth of the interval)
      #     sample_rate: 1.0,          # fraction of intervals measured (< 1 needs Ruby 3.2+)
      #     max_buffered_lines: 1_000_000  # ceiling on lines retained across failed flushes
      #   )
      #
      # In a forking server, call this from the worker-boot hook (Puma's
      # `on_worker_boot`, Unicorn's `after_fork`): the flush thread does
      # not survive a fork, and `start` in the child picks the inherited
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

      # Both are small Integers, so identity settles it: a measurement
      # belongs to the process that started it and to no other.
      def running?
        !!@running && @pid.equal?(Process.pid)
      end

      # Drain the runtime's oneshot table and hand the accumulated delta
      # to the sink. Called by the flush thread every interval; public so
      # a deploy hook (or a signal handler) can force one. Returns
      # whether the sink accepted the data (an empty delta counts as
      # accepted).
      def flush
        return false unless running?

        @mutex.synchronize do
          pull_pending
          push_pending
        end
      end

      # Stop measuring: wind down the flush thread, deliver the final
      # delta, and halt the runtime's instrumentation. Returns false
      # when nothing was running.
      def stop # rubocop:disable Naming/PredicateMethod -- a command that reports whether it acted
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

      # @api private — clears module state between tests. The at_exit
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

      # nil means "default to a tenth of the interval" (see `configure`).
      def validate_jitter!(flush_jitter)
        return if flush_jitter.nil? || (flush_jitter.is_a?(Numeric) && flush_jitter >= 0)

        raise Error, "flush_jitter must be a non-negative number of seconds"
      end

      # Take ownership of the Coverage runtime, or decline. A running
      # Coverage belongs to someone else (a test suite, another tool) —
      # unless this very module started it before a fork, in which case
      # the child inherits the measurement and only needs its own flush
      # thread.
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

      # Wait out the interval (waking early when `stop` signals), then
      # run a cycle. The condition variable rather than a bare sleep is
      # what lets `stop` return promptly instead of waiting out a long
      # interval.
      def flush_loop
        @mutex.synchronize do
          while @running
            @waiter.wait(@mutex, next_wait)
            cycle if @running
          end
        end
      end

      # The interval plus a fresh random share of the jitter, drawn per
      # wait: a fleet of workers booted together (one worker-boot hook
      # starting them all) would otherwise contend on the shared sink at
      # the same instant every interval, forever.
      def next_wait
        @flush_interval + (rand * @flush_jitter)
      end

      # Both call sites run only after `configure` (stop requires
      # running?; reset! guards on the thread the same start spawned),
      # so the mutex pair is always present here.
      def wake_flush_thread
        @mutex.synchronize { @waiter.signal }
      end

      # One interval's work, mutex held: decide whether the next
      # interval measures, then drain and deliver.
      def cycle
        resample
        pull_pending
        push_pending
      end

      # Duty-cycle sampling: with `sample_rate` 0.25, roughly one
      # interval in four measures and the rest are suspended, capping
      # steady-state overhead while every line still gets its chance
      # over time. The first interval after `start` always measures.
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

      # Drain the runtime's oneshot table into the pending buffer.
      # Clearing on read means a line executed again later re-reports,
      # which is what lets a dropped buffer heal for still-hot code.
      def pull_pending
        Coverage.result(stop: false, clear: true).each do |path, data|
          lines = data[:oneshot_lines]
          next if lines.nil? || lines.empty?

          relative = relativize(path)
          next unless relative

          (@pending[relative] ||= Set.new).merge(lines)
        end
      end

      # Deliver the pending buffer to the sink. On failure the buffer is
      # kept for the next interval (the sink being briefly unreachable
      # must not lose data), bounded by the ceiling so a long outage
      # cannot grow memory without limit.
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

      # Oneshot's re-reporting is what makes dropping safe-ish: lines
      # still being executed will report again after the drop, and only
      # code that ran during the outage and never again is lost.
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

      def warn_decline(reason) # rubocop:disable Naming/PredicateMethod -- the callers' falsy return value
        warn "[SimpleCov::Production] not starting: #{reason}"
        false
      end

      def install_at_exit
        return if @at_exit_installed

        @at_exit_installed = true
        at_exit do
          # simplecov:disable — at_exit fires after the suite's own
          # dogfood report has been generated, so this frame can never
          # be observed by it. `stop` carries the logic, declines when
          # nothing is running, and is covered directly.
          stop
          # simplecov:enable
        end
      end
    end
  end
  # rubocop:enable Metrics/ModuleLength, Metrics/ClassLength
end

require_relative "production/file_sink"
