# frozen_string_literal: true

module SimpleCov
  class TestTracker
    module Accessors
      # Records the block's coverage delta as covered by `test_id`, returning the
      # block's value. This is the seam test frameworks hang per-test tracking on. A
      # no-op, with the block still running, unless `track_tests` is enabled and
      # tracking has started, so callers never guard it.
      def track_test(test_id, &)
        tracker = test_tracker
        return yield unless tracker

        tracker.track(test_id, &)
      end

      def test_tracker
        @test_tracker
      end

      # @api private. Reuses the tracker across repeated `start` calls for the same
      # reason `Coverage` keeps counting across them: restarting must not lose what
      # the process already recorded. The framework hooks are only wired up on the
      # first.
      def start_test_tracking
        validate_test_tracking!
        return unless track_tests? && test_tracker.nil?

        @test_tracker = TestTracker.new(granularity: track_tests_granularity)
        TestTracker.install_framework_hooks
      end
    end
  end
end
