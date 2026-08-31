# frozen_string_literal: true

# simplecov:disable
# Methods below only fire under a parallel test runner; not reachable
# from a single-process rspec run. Cucumber's test_projects exercise
# the parallel_tests integration end-to-end in subprocesses, but
# those subprocesses don't merge their Coverage data back into the
# parent this dogfood report measures.
module SimpleCov
  class << self
    # @api private
    def final_result_process?
      adapter = ParallelAdapters.current
      # A subprocess forked while coverage was running is never the final
      # reporter: the process that spawned it merges every slice and produces
      # the report. Without this, fork-based runners that don't set
      # TEST_ENV_NUMBER (Minitest's `parallelize`) have every worker produce
      # the final report and its warnings (#1171).
      return !forked_subprocess? unless adapter

      adapter.first_worker?
    end

    # @api private
    def wait_for_other_processes
      adapter = ParallelAdapters.current
      return unless adapter && final_result_process?

      # Adapters that wrap a runner with a real "wait" primitive implement
      # this; the rest no-op and rely on the polling fallback below.
      adapter.wait_for_siblings

      # The native wait can return before sibling at_exit handlers finish
      # writing resultsets, and adapters without a native wait have nothing
      # else. Either way, poll the resultset cache until all expected workers
      # have reported or a timeout is reached. The outcome is captured so
      # threshold checks can be suppressed against a partial total.
      @parallel_results_complete =
        wait_for_parallel_results(adapter.expected_worker_count, native_wait: adapter.native_wait?)
    end

    # @api private -- true when every sibling reported its resultset before the
    # wait deadline. Defaults to true outside a parallel run.
    def parallel_results_complete?
      instance_variable_defined?(:@parallel_results_complete) ? @parallel_results_complete : true
    end

    # @api private -- seconds the resultset count must hold steady, after a
    # native wait, before we accept fewer than `expected` workers as final.
    PARALLEL_RESULTS_SETTLE = 0.5
    private_constant :PARALLEL_RESULTS_SETTLE

    # @api private -- true when the reporting worker has every resultset it's
    # going to get, false on timeout. Single-process runs short-circuit.
    #
    # Normally we poll until `expected` workers have reported or
    # `SimpleCov.parallel_wait_timeout` elapses. When a native wait already
    # confirmed every sibling process exited, no further resultset will appear,
    # so a count below `expected` just means some workers produced none, and
    # once the count holds steady for `PARALLEL_RESULTS_SETTLE` we accept it as
    # final. Without a native wait we can't tell an idle worker from a slow
    # one, so we keep waiting the full timeout.
    def wait_for_parallel_results(expected, native_wait: false)
      return true unless expected > 1 # simplecov:disable branch — only false in real parallel runs

      deadline = monotonic_time + parallel_wait_timeout
      tracker = {count: 0, since: monotonic_time}
      loop do
        seen = current_parallel_worker_count
        return true if seen >= expected
        return true if native_wait && resultset_count_settled?(tracker, seen)
        return false if parallel_wait_timed_out?(deadline, expected, seen)

        sleep 0.1
      end
    end

    def current_parallel_worker_count
      resultset = ResultMerger.read_resultset
      ResultMerger.worker_identities_for_run(resultset, run_id, process_start_time).size
    end

    # `tracker` carries the last count and the time it last changed across poll
    # iterations. Answered through an if/else rather than an early return
    # because falling through after a climb would read the clock a second time
    # and answer the same `false` anyway.
    def resultset_count_settled?(tracker, count)
      if count > tracker.fetch(:count)
        tracker[:count] = count
        tracker[:since] = monotonic_time
        false
      else
        count.positive? && (monotonic_time - tracker.fetch(:since)) >= PARALLEL_RESULTS_SETTLE
      end
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # @api private -- warns on the first timeout so the user knows the merged
    # total is partial.
    def parallel_wait_timed_out?(deadline, expected, seen)
      return false unless monotonic_time > deadline

      warn_about_incomplete_parallel_results(expected, seen)
      true
    end

    # @api private
    def warn_about_incomplete_parallel_results(expected, seen)
      return unless print_errors

      warn Color.colorize(
        "Only #{seen} of #{expected} parallel-test workers reported within " \
        "#{parallel_wait_timeout}s, so coverage totals are partial and minimum / " \
        "maximum coverage checks are skipped for this run. Increase " \
        "SimpleCov.parallel_wait_timeout if a worker routinely needs longer.",
        :yellow
      )
    end
  end
end
# simplecov:enable
