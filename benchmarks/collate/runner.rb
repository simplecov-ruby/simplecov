# frozen_string_literal: true

require_relative "breakdown"
require_relative "fixture"
require_relative "report"
require_relative "rss_sampler"

module CollateBenchmark
  class Runner
    PHASES = %w[merge build_result store format thresholds].freeze
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
      phase("build_result") { result = SimpleCov::ResultMerger.create_result(*merged, tracked_files: []) }
      phase("store") { SimpleCov::ResultMerger.store_result(result) }
      phase("format") { result.format! }
      phase("thresholds") { SimpleCov.result_exit_status(result) }

      @files_reported = result&.files&.size
    end

    def merge_coverage(paths)
      return serial_merge_coverage(paths) if processes < 2

      SimpleCov::ParallelResultMerger.absorb_results(paths, processes: processes, ignore_timeout: true) ||
        serial_merge_coverage(paths)
    end

    def serial_merge_coverage(paths)
      SimpleCov::ResultMerger.absorb_results(with_progress(paths), ignore_timeout: true)
    end

    def with_progress(paths)
      Enumerator.new do |yielder|
        paths.each_with_index do |path, index|
          progress(index + 1, paths.size)
          yielder << path
        end
      end
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
