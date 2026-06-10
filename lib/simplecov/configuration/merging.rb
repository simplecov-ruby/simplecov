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
      return @enable_for_subprocesses if defined?(@enable_for_subprocesses) && value.nil?

      @enable_for_subprocesses = value || false
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

    # DEPRECATED: alias for `merging`. Same value, same behavior.
    def use_merging(use = nil)
      SimpleCov::Deprecation.warn("`SimpleCov.use_merging` is deprecated. " \
                                  "Replace with `SimpleCov.merging` (same value, same behavior).")
      @use_merging = use unless use.nil?
      @use_merging = true unless defined?(@use_merging) && @use_merging == false
    end

    #
    # Defines the maximum age (in seconds) of a resultset to still be
    # included in merged results. Default is 600 seconds (10 minutes).
    #
    def merge_timeout(seconds = nil)
      @merge_timeout = seconds if seconds.is_a?(Integer)
      @merge_timeout ||= 600
    end
  end
end
