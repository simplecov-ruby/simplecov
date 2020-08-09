# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    class MaximumCoverageDropCheck
      def initialize(result, maximum_coverage_drop)
        @result = result
        @maximum_coverage_drop = maximum_coverage_drop
      end

      def failing?
        return false unless maximum_coverage_drop && last_run

        coverage_diff > maximum_coverage_drop
      end

      def report
        $stderr.printf(
          "Coverage has dropped by %<drop_percent>.2f%% since the last time (maximum allowed: %<max_drop>.2f%%).\n",
          drop_percent: coverage_diff,
          max_drop: maximum_coverage_drop
        )
      end

      def exit_code
        SimpleCov::ExitCodes::MAXIMUM_COVERAGE_DROP
      end

    private

      attr_reader :result, :maximum_coverage_drop

      def last_run
        return @last_run if defined?(@last_run)

        @last_run = SimpleCov::LastRun.read
      end

      def coverage_diff
        raise "Trying to access coverage_diff although there is no last run" unless last_run

        @coverage_diff ||= last_run[:result][:covered_percent] - covered_percent
      end

      def covered_percent
        SimpleCov.round_coverage(result.covered_percent)
      end
    end
  end
end
