# frozen_string_literal: true

require_relative "parallel_adapters/base"
require_relative "parallel_adapters/parallel_tests"
require_relative "parallel_adapters/generic"

module SimpleCov
  # Registry + selection for parallel-test-runner adapters. An adapter
  # answers a small fixed set of questions on SimpleCov's behalf:
  #
  #   - `active?` — are WE the runner in charge for this process?
  #   - `first_worker?` — should this process do the final-result work?
  #   - `wait_for_siblings` — block until siblings finish (optional)
  #   - `expected_worker_count` — how many workers total
  #
  # `SimpleCov::ParallelAdapters::Base` provides safe no-op defaults; two
  # adapters ship out of the box:
  #
  #   - `ParallelTestsAdapter` — wraps the grosser/parallel_tests gem
  #     (precise sync + first-process detection via the gem's own API).
  #   - `GenericAdapter` — env-var-only detection for runners that follow
  #     the parallel_tests `TEST_ENV_NUMBER` convention but don't ship a
  #     Ruby API (parallel_rspec, custom CI sharding, knapsack-style
  #     splitters). See https://github.com/simplecov-ruby/simplecov/issues/1065.
  #
  # Users can plug in additional adapters:
  #
  #   SimpleCov::ParallelAdapters.register MyRunnerAdapter
  #
  # An adapter just needs to be a class responding to the four methods
  # above. Subclass `SimpleCov::ParallelAdapters::Base` to inherit the
  # no-op defaults and override only what you need (the contract methods
  # are defined as class methods, so plain inheritance is what carries
  # them through; `extend Base` won't pick them up).
  module ParallelAdapters
  module_function

    # Adapters in selection order. ParallelTestsAdapter first (most
    # specific — uses the gem's own API when the gem is loaded); then
    # GenericAdapter as the env-var fallback. User-registered adapters
    # are prepended (#register puts new entries at the front) so
    # downstream code can override the built-ins by registering a more
    # specific match.
    def adapters
      @adapters ||= [ParallelTestsAdapter, GenericAdapter]
    end

    # Register a custom adapter. Newly registered adapters are inserted
    # at the front of the selection list so a custom adapter for a
    # specific runner takes precedence over the built-in ParallelTests
    # and Generic adapters.
    #
    #   class MyRunnerAdapter < SimpleCov::ParallelAdapters::Base
    #     def self.active?       = ENV["MY_RUNNER_PID"]
    #     def self.first_worker? = ENV["MY_RUNNER_PID"].to_i == 1
    #     def self.expected_worker_count = ENV["MY_RUNNER_WORKERS"].to_i
    #   end
    #
    #   SimpleCov::ParallelAdapters.register MyRunnerAdapter
    def register(adapter)
      reset_current!
      adapters.unshift(adapter) unless adapters.include?(adapter)
      adapter
    end

    # The adapter SimpleCov should consult for this process — the first
    # registered adapter whose `active?` returns true. Returns nil when
    # no adapter is active (i.e., we're not running under any recognized
    # parallel test runner), in which case the caller should treat the
    # process as single-worker.
    def current
      return @current if defined?(@current)

      @current = adapters.find(&:active?)
    end

    # Clear the memoized `current` selection. Primarily for tests that
    # mutate env vars between examples; production runs are single-shot.
    def reset_current!
      remove_instance_variable(:@current) if defined?(@current)
    end
  end
end
