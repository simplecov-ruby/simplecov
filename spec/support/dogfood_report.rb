# frozen_string_literal: true

require "fileutils"
require "json"
require "simplecov/atomic_file"

module DogfoodReport
  OUTPUT_DIR = "tmp/dogfood"
  PARTIALS_ROOT = "tmp/dogfood-partials"

  PARTIAL_TIMEOUT = 900

  THRESHOLDS = {
    "ruby" => {line: 100.0, branch: 100.0, method: 100.0},
    "jruby" => {line: 96.5}
  }.freeze

  extend self

  def generate
    contexts, coverage = final_coverage

    if parallel_worker?
      store_partial(coverage)
      return unless first_worker?

      wait_for_sibling_partials
      coverage = merged_partials
    end
    report(coverage, contexts)
  end

  def final_coverage
    final = Coverage.result
    contexts = SimpleCov.test_tracker&.recorded_map(closing: final)
    [contexts, SimpleCov::ResultAdapter.call(SimpleCov::UselessResultsRemover.call(final))]
  end

  def parallel_worker?
    !SPEC_PARALLEL_WORKER.nil?
  end

  def first_worker?
    ["", "1"].include?(SPEC_PARALLEL_WORKER)
  end

  def partials_dir
    File.join(PARTIALS_ROOT, File.basename(SPEC_PARALLEL_PID_FILE || "run"))
  end

  # Atomically, because the first worker is reading this directory while the
  # others write into it and a half-written partial is not valid JSON.
  def store_partial(coverage)
    partial = {"dogfood worker #{SPEC_PARALLEL_WORKER}" => {"coverage" => coverage, "timestamp" => Time.now.to_f}}
    SimpleCov::AtomicFile.write(File.join(partials_dir, "worker#{SPEC_PARALLEL_WORKER}.json"), JSON.dump(partial))
  end

  # Called as the suite starts, so that the worker merging the results can tell
  # how many it is waiting for. Neither of the things parallel_tests offers can
  # say: PARALLEL_TEST_GROUPS is the process count that was asked for, before
  # the groups that came out empty are dropped, and the pid file is written by
  # ParallelTests::Pids#add, which appends to a shared array outside its own
  # mutex. Under JRuby's real threads those appends are lost, so the file names
  # fewer workers than are running, which is what used to end this wait early
  # and merge a fraction of the coverage.
  def announce
    return unless parallel_worker?

    FileUtils.mkdir_p(partials_dir)
    FileUtils.touch(File.join(partials_dir, "worker#{SPEC_PARALLEL_WORKER}.started"))
  end

  # The timeout is only a backstop against a worker that dies without writing,
  # so that it says so rather than hanging until the job's own timeout.
  def wait_for_sibling_partials
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + PARTIAL_TIMEOUT
    until partial_paths.size >= started_paths.size
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        raise "dogfood coverage waited #{PARTIAL_TIMEOUT}s for #{started_paths.size} " \
          "workers' partials and has #{partial_paths.size}"
      end

      sleep 0.1
    end
  end

  def started_paths
    Dir.glob(File.join(partials_dir, "worker*.started"))
  end

  def partial_paths
    Dir.glob(File.join(partials_dir, "worker*.json"))
  end

  def merged_partials
    SimpleCov::ResultMerger.merge_results(*partial_paths, ignore_timeout: true).original_result
  end

  def report(coverage, contexts = nil)
    extra_filters = %w[/spec/ /test_projects/ /tmp/].map { |path| SimpleCov::StringFilter.new(path) }
    extra_filters << SimpleCov::StringFilter.new("parallel_result_merger.rb") unless FORK_SUPPORTED

    SimpleCov.enable_coverage :branch if SimpleCov.branch_coverage_supported?
    SimpleCov.enable_coverage :method if SimpleCov.method_coverage_supported?
    filter_config = SimpleCov::Result::FilterConfig.new(filters: SimpleCov.filters + extra_filters, groups: {})
    result = SimpleCov::Result.new(coverage, contexts: contexts, filter_config: filter_config)

    previous_stderr = $stderr
    $stderr = STDERR
    $stdout.puts

    begin
      SimpleCov::Formatter::HTMLFormatter.new(output_dir: OUTPUT_DIR).format(result)

      exit_status = SimpleCov::ExitCodes::ExitCodeHandling.call(result, coverage_limits: coverage_limits)
      return unless exit_status.positive?

      warn "SimpleCov failed with exit #{exit_status} due to a coverage related error"
      Kernel.exit(exit_status)
    ensure
      $stderr = previous_stderr
    end
  end

  def coverage_limits
    limits = {
      minimum_coverage: THRESHOLDS[RUBY_ENGINE] || {},
      minimum_coverage_by_file: {}, minimum_coverage_by_file_overrides: {},
      minimum_coverage_by_group: {}, maximum_coverage: {}, maximum_coverage_drop: {},
      maximum_missed: {}, maximum_missed_per_file: {}, maximum_missed_per_file_overrides: {},
      baseline: nil
    }
    Data.define(*limits.keys).new(**limits)
  end
end
