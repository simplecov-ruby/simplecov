# frozen_string_literal: true

require_relative "base"

module SimpleCov
  module ParallelAdapters
    # Adapter for [grosser/parallel_tests](https://github.com/grosser/parallel_tests).
    # This is the historical default — SimpleCov has special-cased
    # parallel_tests since 0.18 — and remains the most precise option for
    # projects on it. Detection is the standard pair: the `ParallelTests`
    # constant has been loaded AND `TEST_ENV_NUMBER` is set. The gem itself
    # is autoloaded lazily on first `active?` check so users who don't have
    # it installed see no warnings (see #1018).
    class ParallelTestsAdapter < Base
      class << self
        def active?
          ensure_loaded
          # !! to coerce `defined?` (returns nil or "constant") to a proper bool.
          !!(defined?(::ParallelTests) && !ENV.fetch("TEST_ENV_NUMBER", nil).nil?)
        end

        # Pick the *first* started process to do the final-result work,
        # not the last. The parallel_tests README recommends
        # `first_process?` for "do something once after every worker
        # finishes" hooks, so user code that has its own
        # `wait_for_other_processes_to_finish` in an `RSpec.after(:suite)`
        # overwhelmingly waits in the first process — picking the same
        # side avoids the cross-process deadlock #922 reported. Also
        # handles `PARALLEL_TEST_GROUPS=1` naturally (the only worker's
        # `TEST_ENV_NUMBER` is "" and `first_process?` tests for that
        # empty string).
        def first_worker?
          ::ParallelTests.first_process?
        end

        def wait_for_siblings
          ::ParallelTests.wait_for_other_processes_to_finish
        end

        def expected_worker_count
          ENV["PARALLEL_TEST_GROUPS"]&.to_i || 1
        end

        # Auto-require `parallel_tests` when it's installed AND the env
        # vars it sets are present, so callers can rely on
        # `defined?(::ParallelTests)` downstream. parallel_tests is an
        # optional dependency (see https://github.com/grosser/parallel_tests/issues/772),
        # and `TEST_ENV_NUMBER` / `PARALLEL_TEST_GROUPS` are commonly set
        # for other reasons (custom subprocess coordination, CI sharding,
        # the parallel_rspec gem which intentionally mirrors the env-var
        # convention), so a missing gem is treated as "user isn't using
        # parallel_tests" — silently skip and let GenericAdapter handle
        # it. Users who want to override the auto-detect can set
        # `SimpleCov.parallel_tests true` (force on) or `false` (force
        # off). See #1018.
        def ensure_loaded
          return if defined?(::ParallelTests) # simplecov:disable — only true after a previous load
          return if SimpleCov.parallel_tests == false # simplecov:disable — only fires when user opts out
          # simplecov:disable — env-var-only path
          return unless SimpleCov.parallel_tests || env_suggests_parallel_tests?

          # simplecov:disable — only fires under a real parallel_tests setup
          require "parallel_tests"
        rescue LoadError
          # Gem isn't installed; stay quiet — warning here regressed
          # users who use those env vars for their own subprocess
          # coordination.
          # simplecov:enable
        end

        def env_suggests_parallel_tests?
          !ENV.fetch("TEST_ENV_NUMBER", nil).nil? && !ENV.fetch("PARALLEL_TEST_GROUPS", nil).nil?
        end
      end
    end
  end
end
