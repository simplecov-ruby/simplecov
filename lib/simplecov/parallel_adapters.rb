# frozen_string_literal: true

require_relative "parallel_adapters/base"
require_relative "parallel_adapters/parallel_tests"
require_relative "parallel_adapters/generic"

module SimpleCov
  # Registry and selection for parallel-test-runner adapters. An adapter
  # answers a small fixed set of questions on SimpleCov's behalf: `active?`,
  # `first_worker?`, `wait_for_siblings`, and `expected_worker_count`.
  #
  # `Base` provides safe no-op defaults. `ParallelTestsAdapter` wraps the
  # grosser/parallel_tests gem; `GenericAdapter` is env-var-only detection for
  # runners that follow the `TEST_ENV_NUMBER` convention without shipping a
  # Ruby API (#1065, #1156).
  #
  # Users register their own with `ParallelAdapters.register MyAdapter`.
  # Subclass `Base` to inherit the no-op defaults: the contract methods are
  # class methods, so plain inheritance is what carries them through and
  # `extend Base` won't pick them up.
  module ParallelAdapters
    extend self

    # ParallelTestsAdapter first (most specific: it uses the gem's own API when
    # the gem is loaded), then GenericAdapter as the env-var fallback.
    # User-registered adapters are prepended.
    def adapters
      @adapters ||= [ParallelTestsAdapter, GenericAdapter]
    end

    # Newly registered adapters are inserted at the front of the selection
    # list, so a custom adapter for a specific runner takes precedence over the
    # built-ins.
    def register(adapter)
      reset_current!
      adapters.unshift(adapter) unless adapters.include?(adapter)
      adapter
    end

    # The first registered adapter whose `active?` answers true, or nil when
    # none is, in which case the caller treats the process as single-worker.
    def current
      return @current if instance_variable_defined?(:@current)

      @current = adapters.find(&:active?)
    end

    # Primarily for tests that mutate env vars between examples; production
    # runs are single-shot.
    def reset_current!
      remove_instance_variable(:@current) if instance_variable_defined?(:@current)
    end
  end
end
