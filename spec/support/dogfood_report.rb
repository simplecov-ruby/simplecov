# frozen_string_literal: true

require "json"
require "fileutils"

module DogfoodReport
  OUTPUT_DIR = "tmp/dogfood"
  PARTIALS_ROOT = "tmp/dogfood-partials"

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

      wait_for_sibling_workers
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

  def store_partial(coverage)
    FileUtils.mkdir_p(partials_dir)
    partial = {"dogfood worker #{SPEC_PARALLEL_WORKER}" => {"coverage" => coverage, "timestamp" => Time.now.to_f}}
    File.write(File.join(partials_dir, "worker#{SPEC_PARALLEL_WORKER}.json"), JSON.dump(partial))
  end

  def wait_for_sibling_workers
    require "parallel_tests"
    ENV["TEST_ENV_NUMBER"] = SPEC_PARALLEL_WORKER
    ENV["PARALLEL_PID_FILE"] = SPEC_PARALLEL_PID_FILE
    ParallelTests.wait_for_other_processes_to_finish
  ensure
    ENV.delete("TEST_ENV_NUMBER")
    ENV.delete("PARALLEL_PID_FILE")
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
