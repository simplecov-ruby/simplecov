# frozen_string_literal: true

require_relative "base"

module SimpleCov
  module ParallelAdapters
    # Adapter for grosser/parallel_tests, the historical default and still the
    # most precise option for projects on it. Detection requires the full native
    # coordination contract: the `ParallelTests` constant loaded,
    # `TEST_ENV_NUMBER` set, and `PARALLEL_PID_FILE` set, because the native
    # wait API reads the pid-file path with `ENV.fetch`. A runner that only
    # provides the env-var convention belongs to GenericAdapter.
    class ParallelTestsAdapter < Base
      class << self
        def active?
          return false if forced_off?

          ensure_loaded
          !!(defined?(::ParallelTests) && native_parallel_tests_environment?)
        end

        # The first started process, not the last. The parallel_tests README
        # recommends `first_process?` for "do something once after every worker
        # finishes" hooks, so user code with its own
        # `wait_for_other_processes_to_finish` overwhelmingly waits in the first
        # process, and picking the same side avoids the cross-process deadlock #922
        # reported.
        def first_worker?
          ParallelTests.first_process?
        end

        def wait_for_siblings
          return unless native_parallel_tests_environment?

          ParallelTests.wait_for_other_processes_to_finish
        end

        def native_wait?
          native_parallel_tests_environment?
        end

        def expected_worker_count
          parallel_test_groups_count
        end

        # parallel_tests is an optional dependency, and `TEST_ENV_NUMBER` /
        # `PARALLEL_TEST_GROUPS` are commonly set for other reasons, so a missing
        # gem is treated as "user isn't using parallel_tests": stay quiet and let
        # GenericAdapter handle it. Warning here regressed users who use those env
        # vars for their own subprocess coordination (#1018).
        def ensure_loaded
          return if defined?(::ParallelTests)
          return if forced_off?
          return unless SimpleCov.parallel_tests || env_suggests_parallel_tests?

          # simplecov:disable — only fires under a real parallel_tests setup
          require "parallel_tests"
        rescue LoadError
          # simplecov:enable
        end

        def env_suggests_parallel_tests?
          ENV.key?("TEST_ENV_NUMBER") && ENV.key?("PARALLEL_TEST_GROUPS")
        end

        def native_parallel_tests_environment?
          ENV.key?("TEST_ENV_NUMBER") && ENV.key?("PARALLEL_PID_FILE")
        end
      end
    end
  end
end
