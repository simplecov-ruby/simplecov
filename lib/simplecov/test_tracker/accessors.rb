# frozen_string_literal: true

module SimpleCov
  class TestTracker
    # The tracker's singleton-side surface, extended onto `SimpleCov` (see
    # the requires in simplecov.rb, and `RunIdentity::Accessors` for the
    # same pattern).
    module Accessors
      # Record the block's coverage delta as covered by `test_id`,
      # returning the block's value. This is the seam test frameworks hang
      # per-test tracking on: SimpleCov wraps RSpec examples and Minitest
      # tests itself, and any other runner can wrap its own units of work
      # the same way. A no-op (the block still runs) unless `track_tests`
      # is enabled and tracking has started, so callers never guard it.
      def track_test(test_id, &)
        tracker = test_tracker
        return yield unless tracker

        tracker.track(test_id, &)
      end

      # @api private — the live per-test recorder, present only while
      # tracking runs with `track_tests` enabled.
      def test_tracker
        @test_tracker
      end

      # @api private — called from `start_coverage_measurement`. Reuses the
      # tracker across repeated `start` calls for the same reason
      # `Coverage` keeps counting across them: restarting must not lose
      # what the process already recorded — and the framework hooks are
      # only wired up on the first.
      def start_test_tracking
        validate_test_tracking!
        return unless track_tests? && test_tracker.nil?

        @test_tracker = TestTracker.new(granularity: track_tests_granularity)
        TestTracker.install_framework_hooks
      end
    end
  end
end
