# frozen_string_literal: true

module SimpleCov
  module ParallelAdapters
    # Default no-op implementations for a parallel-test-runner adapter.
    # Everything not overridden falls back to behaving like a single-process
    # run. Adapters are classes, used as singletons and never instantiated.
    class Base
      class << self
        def active?
          false
        end

        def first_worker?
          true
        end

        def wait_for_siblings; end

        # Whether `wait_for_siblings` blocks until every sibling process has exited,
        # so no further resultset can appear. When true, the reporting worker can
        # accept a settled resultset count below `expected_worker_count` as final
        # instead of waiting out the whole `parallel_wait_timeout`.
        def native_wait?
          false
        end

        def expected_worker_count
          1
        end

        # mutant:disable — `false` is a singleton, so comparing against
        # it answers the same through ==, eql? and equal?, and no
        # example can tell the three apart.
        def forced_off?
          SimpleCov.parallel_tests == false
        end

        # Unset, empty, non-numeric, and non-positive values all mean 1: an
        # unparseable value must not yield 0 workers, which would end the sibling
        # wait before it started.
        def parallel_test_groups_count
          count = Integer(ENV.fetch("PARALLEL_TEST_GROUPS", nil), exception: false)
          count&.positive? ? count : 1
        end
      end
    end
  end
end
