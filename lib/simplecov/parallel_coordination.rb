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
      adapter = SimpleCov::ParallelAdapters.current
      return true unless adapter

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
      # expected workers have reported or a timeout is reached.
      wait_for_parallel_results(adapter.expected_worker_count)
    end

    # @api private
    def wait_for_parallel_results(expected)
      return unless expected > 1 # simplecov:disable branch — only false in real parallel runs

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
      loop do
        resultset = SimpleCov::ResultMerger.read_resultset
        break if resultset.size >= expected
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

        sleep 0.1
      end
    end
  end
end
# simplecov:enable
