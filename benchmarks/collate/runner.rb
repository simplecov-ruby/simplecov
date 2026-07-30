# frozen_string_literal: true

require_relative "breakdown"
require_relative "fixture"
require_relative "report"
require_relative "rss_sampler"

module CollateBenchmark
  # Runs the steps `SimpleCov.collate` runs, in the same order, with a timer
  # around each.
  #
  # `collate` itself isn't called because it ends in `Kernel.exit`, and because
  # a single total wouldn't say which step a change moved. The phases are split
  # exactly where `ResultMerger.merge_results` splits internally, so `merge`
  # covers reading and folding the shards and `build_result` covers turning the
  # folded coverage into `SimpleCov::SourceFile`s.
  class Runner
    PHASES = %w[merge build_result store format thresholds].freeze
    # `merge` and `build_result` produce the inputs every later phase needs, so
    # only the three trailing phases can be dropped from a run.
    SKIPPABLE_PHASES = %w[store format thresholds].freeze

    attr_reader :label, :scale, :skip, :breakdown, :processes, :resultsets_used

    def initialize(options)
      @label = options.label
      @requested_resultsets = options.resultsets
      @scale = options.scale
      @skip = options.skip
      @rebuild = options.rebuild
      @baseline_label = options.baseline
      @breakdown = options.breakdown
      @processes = options.processes
      @timings = {}
    end

    def call
      fixture = Fixture.prepare(scale: @scale, resultsets: @requested_resultsets, force: @rebuild)
      @resultsets_used = fixture.resultset_paths.size
      configure(fixture)
      install_breakdown if @breakdown

      report = Report.new(run: self, timings: @timings, baseline_label: @baseline_label)
      report.header(fixture)
      peak_rss = measure(fixture)
      report.call(peak_rss: peak_rss, files_reported: @files_reported)
    end

  private

    # The counters live in whichever process ran the wrapped method, so a
    # forked worker's attribution dies with it and the merge row would come
    # back near-empty. Say so rather than print a misleading table.
    def install_breakdown
      if processes > 1
        warn "[#{@label}] BREAKDOWN only attributes work done in this process; " \
             "the workers' share of the merge will be missing"
      end
      Breakdown.install!
    end

    def measure(fixture)
      sampler = RssSampler.new
      run_phases(fixture)
      sampler.stop
    end

    # Mirrors the `SimpleCov.collate` configuration block, plus the two things a
    # real collate gets from its environment: the project root the resultset
    # paths live under, and a coverage dir to write into.
    #
    # `print_errors` is left at its default on purpose — the threshold phase's
    # work includes reporting each violation, and a warning about dropped source
    # files is how we'd learn the fixture had gone stale.
    def configure(fixture)
      SimpleCov.root(fixture.root)
      SimpleCov.coverage_dir(Fixture::COVERAGE_DIR)
      SimpleCov.enable_coverage(:branch)
      SimpleCov.primary_coverage(:branch)
      SimpleCov.formatter = SimpleCov::Formatter::HTMLFormatter
      SimpleCov.coverage(:line) { minimum_per_file 70 }
      SimpleCov.coverage(:branch) { minimum_per_file 80 }
    end

    def run_phases(fixture)
      merged = nil
      result = nil

      phase("merge") { merged = merge_coverage(fixture.resultset_paths) }
      phase("build_result") { result = SimpleCov::ResultMerger.create_result(*merged) }
      phase("store") { SimpleCov::ResultMerger.store_result(result) }
      phase("format") { result.format! }
      phase("thresholds") { SimpleCov.result_exit_status(result) }

      @files_reported = result&.files&.size
    end

    # With PROCESSES > 1, the fan-out `SimpleCov.collate processes: N` performs —
    # same merge, same visiting order, spread over forked workers. Falls
    # through to the in-process loop if the fan-out bails, which is what
    # `ResultMerger.merge_results` does too.
    def merge_coverage(paths)
      return serial_merge_coverage(paths) if processes < 2

      SimpleCov::ParallelResultMerger.merge_resultsets(paths, processes: processes, ignore_timeout: true) ||
        serial_merge_coverage(paths)
    end

    # `ResultMerger.merge_resultsets`, reproduced here so the per-resultset
    # progress line can be printed, and stopping short of `create_result` so
    # source-file building is timed separately.
    def serial_merge_coverage(paths)
      remaining = paths.dup
      initial = valid_results(remaining.shift)

      remaining.each_with_index.reduce(initial) do |memo, (path, index)|
        progress(index + 2, paths.size)
        SimpleCov::ResultMerger.merge_coverage(memo, valid_results(path))
      end
    end

    def valid_results(path)
      SimpleCov::ResultMerger.valid_results(path, ignore_timeout: true)
    end

    def phase(name)
      return if @skip.include?(name)

      GC.start
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      @timings[name] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      warn("\r[#{@label}] #{name}: #{format('%.2fs', @timings[name])}#{' ' * 20}")
    end

    def progress(done, total)
      return unless $stderr.tty?

      $stderr.print("\r[#{@label}] merge: #{done}/#{total} resultsets")
    end
  end
end
