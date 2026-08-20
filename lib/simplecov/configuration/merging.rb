# frozen_string_literal: true

module SimpleCov
  # Result merging and subprocess / parallel-test coordination:
  # `merging`, `merge_subprocesses`, `merge_timeout`, `parallel_tests`.
  module Configuration
    #
    # Get or set whether SimpleCov should hook `Process._fork` to
    # attach itself to subprocesses. Required when the suite uses
    # parallel test workers (e.g. Rails' `parallelize(workers:)`).
    # Defaults to false.
    #
    def merge_subprocesses(value = nil)
      return @enable_for_subprocesses if defined?(@enable_for_subprocesses) && value.nil?

      @enable_for_subprocesses = value || false
    end

    # @api private — predicate used by `start_tracking` to decide
    # whether to install the fork hook.
    def enabled_for_subprocesses?
      defined?(@enable_for_subprocesses) ? @enable_for_subprocesses : false
    end

    #
    # Get or set whether SimpleCov should auto-require the
    # `parallel_tests` gem when it sees `TEST_ENV_NUMBER` /
    # `PARALLEL_TEST_GROUPS` in the environment. Defaults to auto-detect
    # (nil). See #1018.
    #
    def parallel_tests(value = :__no_arg__)
      return defined?(@parallel_tests) ? @parallel_tests : nil if value == :__no_arg__

      @parallel_tests = value
    end

    # DEPRECATED: alias for `merge_subprocesses`. Same value/behavior.
    def enable_for_subprocesses(value = nil)
      SimpleCov::Deprecation.warn("`SimpleCov.enable_for_subprocesses` is deprecated. " \
                                  "Replace with `SimpleCov.merge_subprocesses` (same value, same behavior).")
      merge_subprocesses(value)
    end

    #
    # Get or set whether to merge results from multiple test suites
    # (test:units, test:functionals, cucumber, ...) into a single
    # coverage report. Defaults to true.
    #
    def merging(use = nil)
      @use_merging = use unless use.nil?
      @use_merging = true unless defined?(@use_merging) && @use_merging == false
      @use_merging
    end

    #
    # Get or set whether SimpleCov's selected final process owns merge processing:
    # waiting for sibling workers, building the merged result, formatting,
    # enforcing thresholds, and writing `.last_run.json`.
    #
    # Defaults to true, except for recognized multi-worker parallel runs
    # that explicitly write to a custom coverage destination while merging
    # is enabled. Those runs are likely using an external `SimpleCov.collate`
    # step to finalize the merge.
    #
    def finalize_merge(value = :__no_arg__)
      unless value == :__no_arg__
        @finalize_merge = value
        @finalize_merge_explicit = true
      end

      return @finalize_merge if defined?(@finalize_merge_explicit) && @finalize_merge_explicit

      inferred = inferred_finalize_merge?
      warn_about_inferred_finalize_merge unless inferred
      inferred
    end

    def finalize_merge?
      finalize_merge
    end

    # @api private
    def merge_finalization_owner?
      collating_result? || (finalize_merge? && final_result_process?)
    end

    # DEPRECATED: alias for `merging`. Same value, same behavior.
    # Delegating (rather than duplicating the body) also fixes the
    # return value: this used to return nil where `merging` returns
    # false, because the final expression was the skipped guard
    # assignment rather than the stored value.
    def use_merging(use = nil)
      SimpleCov::Deprecation.warn("`SimpleCov.use_merging` is deprecated. " \
                                  "Replace with `SimpleCov.merging` (same value, same behavior).")
      merging(use)
    end

    #
    # Defines the maximum age (in seconds) of a resultset to still be
    # included in merged results. Default is 600 seconds (10 minutes).
    #
    # A numeric SIMPLECOV_MERGE_TIMEOUT in the environment takes
    # precedence over the configured value: `simplecov watch` re-runs
    # test subsets across a long session and extends its child runs'
    # merge window this way, where editing every watched project's
    # configuration is not an option.
    #
    def merge_timeout(seconds = nil)
      @merge_timeout = seconds if seconds.is_a?(Integer)
      env_merge_timeout || (@merge_timeout ||= 600)
    end

    def env_merge_timeout
      value = ENV.fetch("SIMPLECOV_MERGE_TIMEOUT", nil)
      value&.match?(/\A\d+\z/) ? Integer(value, 10) : nil
    end

    #
    # Defines how long (in seconds) the reporting process waits for the
    # remaining parallel-test workers to write their resultsets before it
    # proceeds with a partial merge. Default is 60 seconds. Raise it when a
    # slow worker routinely finishes well after the others, so its coverage
    # is still included and the minimum / maximum coverage checks aren't
    # skipped against a partial total.
    #
    def parallel_wait_timeout(seconds = nil)
      @parallel_wait_timeout = seconds if seconds.is_a?(Integer)
      @parallel_wait_timeout ||= 60
    end

  private

    def inferred_finalize_merge?
      return true unless merging

      adapter = SimpleCov::ParallelAdapters.current
      return true unless adapter
      return true unless adapter.expected_worker_count > 1
      return true unless parallel_worker_environment?
      return true unless explicit_custom_coverage_destination?

      false
    end

    def parallel_worker_environment?
      ENV.key?("TEST_ENV_NUMBER") || ENV.key?("PARALLEL_TEST_GROUPS")
    end

    def explicit_custom_coverage_destination?
      return false unless explicit_coverage_destination?

      coverage_path != File.expand_path("coverage", root)
    end

    def explicit_coverage_destination?
      (defined?(@coverage_path_explicit) && @coverage_path_explicit) ||
        (defined?(@coverage_dir_explicit) && @coverage_dir_explicit)
    end

    def warn_about_inferred_finalize_merge
      return if defined?(@finalize_merge_inference_warned) && @finalize_merge_inference_warned
      return unless print_errors

      @finalize_merge_inference_warned = true
      warn SimpleCov::Color.colorize(inferred_finalize_merge_warning, :yellow)
    end

    def inferred_finalize_merge_warning
      "SimpleCov inferred `finalize_merge false` because this parallel worker is merging " \
        "into a custom coverage destination. Set `SimpleCov.finalize_merge false` to keep " \
        "external collation ownership, or `SimpleCov.finalize_merge true` if this worker " \
        "should wait, merge, format, enforce thresholds, and write `.last_run.json`. " \
        "See https://github.com/simplecov-ruby/simplecov#merge-finalization-ownership."
    end
  end
end
