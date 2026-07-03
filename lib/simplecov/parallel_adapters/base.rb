# frozen_string_literal: true

module SimpleCov
  module ParallelAdapters
    # Default no-op implementations for a parallel-test-runner adapter.
    # Real adapters subclass and override what they need; everything else
    # falls back to "behave like a single-process run."
    #
    # Adapters are classes (used as singletons, never instantiated) — they
    # answer a small fixed set of questions about whether THIS worker
    # process is the one that should do final-result work, and provide an
    # optional hook for waiting on sibling workers.
    #
    # @see SimpleCov::ParallelAdapters for the registry and selection.
    class Base
      class << self
        # Should this adapter be selected for the current process? Adapters
        # are tried in registration order; the first one whose `active?`
        # returns true is chosen. Inactive adapters return `false`.
        def active?
          false
        end

        # Among the parallel workers in this run, should THIS worker do
        # the final-result work (wait for siblings, merge resultsets,
        # run threshold checks, format the report)? Default is `true`
        # for the single-process case.
        def first_worker?
          true
        end

        # Optional: block until sibling workers have finished writing
        # their resultsets. An adapter that wraps a parallel-test runner
        # with a native synchronization primitive (e.g., `parallel_tests`'s
        # `wait_for_other_processes_to_finish`) implements this for
        # lower latency; otherwise SimpleCov polls the resultset cache
        # as a fallback (see `SimpleCov.wait_for_parallel_results`).
        def wait_for_siblings
          # No-op default; polling fallback handles correctness.
        end

        # Does `wait_for_siblings` block until every sibling PROCESS has
        # exited (so no further resultset can appear)? When true, the
        # reporting worker can accept a settled resultset count below
        # `expected_worker_count` as final instead of waiting out the whole
        # `parallel_wait_timeout` for workers that produced no coverage.
        # Defaults to false (no native wait; the poll is the only signal).
        def native_wait?
          false
        end

        # How many parallel workers are participating in this run. Used
        # by the polling fallback to know how many resultset entries to
        # expect. Defaults to 1 (single-process).
        def expected_worker_count
          1
        end
      end
    end
  end
end
