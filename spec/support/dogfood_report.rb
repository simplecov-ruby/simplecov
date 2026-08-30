# frozen_string_literal: true

require "json"
require "fileutils"

# The end-of-suite dogfood coverage report: formats simplecov's own
# coverage (tracked by the Coverage.start prelude in spec/helper.rb) and
# enforces the per-engine thresholds below through the same
# ExitCodeHandling path production uses, so contributors see shortfalls
# in exactly the format end users see when minimum_coverage trips.
#
# A serial run reports directly. Under a parallel runner (`rake spec`
# fans the suite out with parallel_rspec) each worker executes only a
# slice of the suite, so per-worker enforcement would fail on partial
# coverage: instead every worker writes its raw coverage as a
# resultset-shaped partial, and the last worker to finish merges all the
# slices through simplecov's own ResultMerger and reports on the union —
# the same store-and-merge dance simplecov performs for its users'
# parallel suites.
module DogfoodReport
  OUTPUT_DIR = "tmp/dogfood"
  PARTIALS_ROOT = "tmp/dogfood-partials"

  # Per-engine thresholds. CRuby is the primary target and is held to
  # 100% on every criterion. JRuby and TruffleRuby `skip` specs that
  # exercise branch / method coverage paths their Coverage module
  # doesn't support, so the lib/ lines those specs would have hit stay
  # uncovered there — set the line threshold a hair below today's
  # actual to act as a regression guard rather than a strict ceiling.
  # (Files that are wholly unreachable on an engine are filtered out
  # in `report` instead, so they don't drag this number down.)
  # Engines absent from this hash get an informational report only,
  # no threshold enforcement.
  THRESHOLDS = {
    "ruby" => {line: 100.0, branch: 100.0, method: 100.0},
    "jruby" => {line: 96.5},
    "truffleruby" => {line: 97.5}
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

  # Taking a coverage result stops measurement, so the tracker's last
  # open segment has to be closed against the same one the report is
  # built from.
  def final_coverage
    final = Coverage.result
    contexts = SimpleCov.test_tracker&.recorded_map(closing: final)
    [contexts, SimpleCov::ResultAdapter.call(SimpleCov::UselessResultsRemover.call(final))]
  end

  # The SPEC_PARALLEL_* constants are the worker identity spec/helper.rb
  # captured before scrubbing the parallel_tests variables from ENV.

  def parallel_worker?
    !SPEC_PARALLEL_WORKER.nil?
  end

  # Worker 1 reports (parallel_tests leaves its TEST_ENV_NUMBER blank
  # unless --first-is-1 makes it "1"). It always exists, whereas the
  # requested worker count can overshoot the number actually spawned
  # when there are fewer spec files than workers.
  def first_worker?
    ["", "1"].include?(SPEC_PARALLEL_WORKER)
  end

  # Partials are keyed by the parallel_tests pid file, which is unique
  # per invocation, so a stale slice left by an aborted run can't leak
  # into a later run's merge.
  def partials_dir
    File.join(PARTIALS_ROOT, File.basename(SPEC_PARALLEL_PID_FILE || "run"))
  end

  def store_partial(coverage)
    FileUtils.mkdir_p(partials_dir)
    partial = {"dogfood worker #{SPEC_PARALLEL_WORKER}" => {"coverage" => coverage, "timestamp" => Time.now.to_f}}
    File.write(File.join(partials_dir, "worker#{SPEC_PARALLEL_WORKER}.json"), JSON.dump(partial))
  end

  # parallel_tests ships this exact wait for end-of-run aggregation; it
  # reads the scrubbed variables, so restore them for the call. Sibling
  # workers write their partial in this same after(:suite) hook before
  # exiting, so once they have exited every slice is on disk.
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

  # Every slice is read back through the resultset parser — this
  # worker's own included — so the combiner sees one uniform
  # JSON-round-tripped shape throughout.
  def merged_partials
    SimpleCov::ResultMerger.merge_results(*partial_paths, ignore_timeout: true).original_result
  end

  def report(coverage, contexts = nil)
    extra_filters = %w[/spec/ /test_projects/ /tmp/].map { |path| SimpleCov::StringFilter.new(path) }
    # `ParallelResultMerger`'s fan-out forks, so where the runtime cannot
    # (JRuby, TruffleRuby, CRuby on Windows) its worker lines are unreachable
    # rather than untested. Drop the file on those engines instead of
    # lowering the bar for every other file; CRuby still holds it to 100%.
    extra_filters << SimpleCov::StringFilter.new("parallel_result_merger.rb") unless FORK_SUPPORTED

    # Enabling :branch / :method is what teaches FileList / Result
    # to surface those data in coverage_statistics. We enable here
    # (rather than in SimpleCov.start) to avoid leaking the
    # multi-criterion output shape into formatter specs that assert
    # against line-only fixtures.
    SimpleCov.enable_coverage :branch if SimpleCov.branch_coverage_supported?
    SimpleCov.enable_coverage :method if SimpleCov.method_coverage_supported?
    filter_config = SimpleCov::Result::FilterConfig.new(filters: SimpleCov.filters + extra_filters, groups: {})
    # Under SIMPLECOV_TRACK_TESTS the tracker has been recording which
    # example covered each line. Hand that map to the result so the
    # report carries it and `simplecov tests` can read it back.
    result = SimpleCov::Result.new(coverage, contexts: contexts, filter_config: filter_config)

    # Leading newline so the formatter's message doesn't fuse onto
    # RSpec's progress-formatter dots when run via `rake spec` / `rspec`.
    # Route through the real STDERR rather than `$stderr` so the
    # formatter's `warn`-based status line and any threshold-violation
    # output survive the FailOnWarnings capture that's installed for
    # the suite (`spec/support/fail_rspec_on_ruby_warning.rb` swaps
    # `$stderr` to a StringIO). Without this, the dogfood report (a
    # contributor-facing health check, not a Ruby warning) would be
    # silently dumped into the tmp warnings file.
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

  # ExitCodeHandling.call just needs an object that responds to the
  # limit readers — building a local Data keeps this helper's coupling
  # to internal API minimal.
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
