# frozen_string_literal: true

require_relative "base"

module SimpleCov
  module ParallelAdapters
    # Catch-all adapter for parallel test runners that follow the
    # `TEST_ENV_NUMBER` / `PARALLEL_TEST_GROUPS` env-var convention but
    # don't ship a Ruby API for SimpleCov to hook (parallel_rspec,
    # knapsack-style splitters, custom CI sharding scripts). Activates
    # when `TEST_ENV_NUMBER` is set; doesn't require any specific gem to
    # be loaded.
    #
    # Heuristic for `first_worker?`: the worker whose `TEST_ENV_NUMBER`
    # is `""` (parallel_tests/parallel_rspec convention) or `"1"`
    # (zero-based runners that start at 1). Any other value is treated
    # as a non-first worker.
    #
    # `wait_for_siblings` is inherited from Base as a no-op — without a
    # runner-provided API the only synchronization available is polling
    # the resultset cache, which `SimpleCov.wait_for_parallel_results`
    # does after the no-op returns.
    class GenericAdapter < Base
      class << self
        def active?
          !ENV.fetch("TEST_ENV_NUMBER", nil).nil?
        end

        # parallel_tests sets the first worker's TEST_ENV_NUMBER to "";
        # parallel_rspec inherits that. Runners that number from 1 use
        # "1" for the first worker. Both shapes match.
        def first_worker?
          ["", "1"].include?(ENV.fetch("TEST_ENV_NUMBER", nil))
        end

        def expected_worker_count
          ENV["PARALLEL_TEST_GROUPS"]&.to_i || 1
        end
      end
    end
  end
end
