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
    # How long the first worker is willing to wait for all sibling
    # workers' resultsets to appear in the cache before proceeding
    # with whatever it has. Tuned generously enough that slow CI
    # runners with one straggler don't trip the "incomplete results"
    # path on a routine basis. See #1065 for the parallel_rspec /
    # GenericAdapter case where there is no native wait primitive
    # and this poll is the only synchronization available.
    PARALLEL_RESULTS_WAIT_TIMEOUT = 60
    private_constant :PARALLEL_RESULTS_WAIT_TIMEOUT

    # @api private
    def final_result_process?
      adapter = SimpleCov::ParallelAdapters.current
      # No recognized parallel-test adapter. A subprocess forked while
      # coverage was running is never the final reporter — the process that
      # spawned it merges every slice and produces the report. Without this,
      # fork-based runners that don't set TEST_ENV_NUMBER (e.g. Minitest's
      # `parallelize`) have every worker produce the final report and its
      # warnings. See issue #1171.
      return !forked_subprocess? unless adapter

      adapter.first_worker?
    end

    # @api private
    def wait_for_other_processes
      adapter = SimpleCov::ParallelAdapters.current
      return unless adapter && final_result_process?

      # Native synchronization first (adapters that wrap a runner with a
      # real "wait" primitive — parallel_tests'
      # `wait_for_other_processes_to_finish` — implement this; adapters
      # without a native API no-op and rely on the polling fallback below).
      adapter.wait_for_siblings

      # The native wait can return before sibling at_exit handlers finish
      # writing resultsets, and adapters without a native wait have
      # nothing else. Either way, poll the resultset cache until all
      # expected workers have reported or a timeout is reached. Capture
      # the outcome so `ready_to_process_results?` can suppress min/max
      # threshold checks against a partial total.
      @parallel_results_complete = wait_for_parallel_results(adapter.expected_worker_count)
    end

    # @api private — true when every sibling reported its resultset
    # before the wait deadline. Defaults to true outside a parallel
    # run (when `wait_for_other_processes` is a no-op).
    def parallel_results_complete?
      defined?(@parallel_results_complete) ? @parallel_results_complete : true
    end

    # @api private — returns true when every expected worker reported
    # before the deadline, false on timeout. Single-process runs
    # (expected <= 1) short-circuit to true with no waiting.
    def wait_for_parallel_results(expected)
      return true unless expected > 1 # simplecov:disable branch — only false in real parallel runs

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + PARALLEL_RESULTS_WAIT_TIMEOUT
      loop do
        seen = SimpleCov::ResultMerger.read_resultset.size
        return true if seen >= expected
        return false if parallel_wait_timed_out?(deadline, expected, seen)

        sleep 0.1
      end
    end

    # @api private — true once the wait deadline has passed; warns on
    # the first timeout so the user knows the merged total is partial.
    def parallel_wait_timed_out?(deadline, expected, seen)
      return false unless Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      warn_about_incomplete_parallel_results(expected, seen)
      true
    end

    # @api private
    def warn_about_incomplete_parallel_results(expected, seen)
      return unless print_errors

      warn SimpleCov::Color.colorize(
        "Only #{seen} of #{expected} parallel-test workers reported within " \
        "#{PARALLEL_RESULTS_WAIT_TIMEOUT}s. Coverage totals are partial; " \
        "minimum / maximum coverage checks are skipped for this run.",
        :yellow
      )
    end
  end
end
# simplecov:enable
