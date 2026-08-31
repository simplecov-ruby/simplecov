# frozen_string_literal: true

require_relative "base"

module SimpleCov
  module ParallelAdapters
    # Catch-all adapter for parallel test runners that follow the
    # `TEST_ENV_NUMBER` / `PARALLEL_TEST_GROUPS` env-var convention but ship no
    # Ruby API for SimpleCov to hook. `wait_for_siblings` is inherited from Base
    # as a no-op: without a runner-provided API the only synchronization
    # available is polling the resultset cache.
    class GenericAdapter < Base
      class << self
        def active?
          return false if forced_off?

          ENV.key?("TEST_ENV_NUMBER")
        end

        # parallel_tests sets the first worker's TEST_ENV_NUMBER to "", and runners
        # that number from 1 use "1". Both shapes match; any other value is a
        # non-first worker.
        def first_worker?
          ["", "1"].include?(ENV.fetch("TEST_ENV_NUMBER", nil))
        end

        def expected_worker_count
          parallel_test_groups_count
        end
      end
    end
  end
end
