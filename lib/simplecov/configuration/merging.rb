# frozen_string_literal: true

module SimpleCov
  module Configuration
    #
    # Whether SimpleCov should hook `Process._fork` to attach itself to
    # subprocesses. Required when the suite uses parallel test workers (Rails'
    # `parallelize(workers:)`). Defaults to false.
    #
    def merge_subprocesses(value = nil)
      return @enable_for_subprocesses if instance_variable_defined?(:@enable_for_subprocesses) && value.nil?

      self.merge_subprocesses = value
      @enable_for_subprocesses
    end

    # false stands in for nothing, so the answer is always a real opt-in or
    # opt-out.
    def merge_subprocesses=(value)
      @enable_for_subprocesses = value || false
    end

    # @api private
    def enabled_for_subprocesses?
      !!@enable_for_subprocesses
    end

    #
    # Whether SimpleCov should auto-require the `parallel_tests` gem when it
    # sees `TEST_ENV_NUMBER` / `PARALLEL_TEST_GROUPS` in the environment.
    # Defaults to auto-detect (nil). See #1018.
    #
    def parallel_tests(value = :__no_arg__)
      return @parallel_tests if value.eql?(:__no_arg__)

      self.parallel_tests = _ = value
    end

    def parallel_tests=(value)
      @parallel_tests = value
    end

    def enable_for_subprocesses(value = nil)
      Deprecation.warn("`SimpleCov.enable_for_subprocesses` is deprecated. " \
                       "Replace with `SimpleCov.merge_subprocesses` (same value, same behavior).")
      merge_subprocesses(value)
    end

    def merging(use = nil)
      self.merging = use unless use.nil?
      # Unset reads as nil, and only an explicit `merging false` turns it off.
      @use_merging = true if @use_merging.nil?
      @use_merging
    end

    def merging=(use)
      @use_merging = use
    end

    #
    # Whether SimpleCov's selected final process owns merge processing: waiting
    # for sibling workers, building the merged result, formatting, enforcing
    # thresholds, and writing `.last_run.json`.
    #
    # Defaults to true, except for recognized multi-worker parallel runs that
    # explicitly write to a custom coverage destination while merging is
    # enabled. Those runs are likely using an external `SimpleCov.collate` step
    # to finalize the merge.
    #
    # Splatted rather than defaulted: false is a value someone sets on purpose,
    # so "given nothing" cannot be told from it by looking at the argument.
    def finalize_merge(*value)
      unless value.empty?
        explicit, = value
        self.finalize_merge = _ = explicit
      end

      return @finalize_merge if @finalize_merge_explicit

      inferred = inferred_finalize_merge?
      warn_about_inferred_finalize_merge unless inferred
      inferred
    end

    # Writing is what makes the answer explicit rather than inferred.
    def finalize_merge=(value)
      @finalize_merge = value
      @finalize_merge_explicit = true
    end

    def finalize_merge?
      finalize_merge
    end

    # @api private
    def merge_finalization_owner?
      collating_result? || (finalize_merge? && final_result_process?)
    end

    def use_merging(use = nil)
      Deprecation.warn("`SimpleCov.use_merging` is deprecated. " \
                       "Replace with `SimpleCov.merging` (same value, same behavior).")
      merging(use)
    end

    #
    # The maximum age (in seconds) of a resultset to still be included in
    # merged results. Default is 600 seconds.
    #
    # A numeric SIMPLECOV_MERGE_TIMEOUT in the environment takes precedence
    # over the configured value: `simplecov watch` re-runs test subsets across
    # a long session and extends its child runs' merge window this way, where
    # editing every watched project's configuration is not an option.
    #
    def merge_timeout(seconds = nil)
      self.merge_timeout = seconds
      # Memoized through a local rather than `|| (@merge_timeout ||= 600)`:
      # steep 2.0's logic-type interpreter crashes on an or-assignment nested in
      # a logical operand, and ivar narrowing doesn't carry across statements
      # the way a local's does.
      configured = @merge_timeout || 600
      @merge_timeout = configured
      env_merge_timeout || configured
    end

    # Anything but an Integer is ignored, the way the dual method always did.
    def merge_timeout=(seconds)
      @merge_timeout = seconds if seconds.instance_of?(Integer)
    end

    def env_merge_timeout
      value = ENV.fetch("SIMPLECOV_MERGE_TIMEOUT", nil)
      Integer(value, 10) if value&.match?(/\A\d+\z/)
    end

    #
    # How long (in seconds) the reporting process waits for the remaining
    # parallel-test workers to write their resultsets before it proceeds with a
    # partial merge. Default is 60 seconds. Raise it when a slow worker
    # routinely finishes well after the others, so its coverage is still
    # included and the threshold checks aren't skipped against a partial total.
    #
    def parallel_wait_timeout(seconds = nil)
      self.parallel_wait_timeout = seconds
      @parallel_wait_timeout ||= 60
    end

    # Anything but an Integer is ignored, the way the dual method always did.
    def parallel_wait_timeout=(seconds)
      @parallel_wait_timeout = seconds if seconds.instance_of?(Integer)
    end

  private

    def inferred_finalize_merge?
      return true unless merging

      adapter = ParallelAdapters.current
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

      !coverage_path.eql?(File.expand_path("coverage", root))
    end

    def explicit_coverage_destination?
      @coverage_path_explicit || @coverage_dir_explicit
    end

    def warn_about_inferred_finalize_merge
      return if @finalize_merge_inference_warned
      return unless print_errors

      @finalize_merge_inference_warned = true
      warn Color.colorize(inferred_finalize_merge_warning, :yellow)
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
