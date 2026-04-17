# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    class MaximumCoverageDropCheck
      def initialize(result, maximum_coverage_drop)
        @result = result
        @maximum_coverage_drop = maximum_coverage_drop
      end

      def failing?
        violations.any?
      end

      def report
        violations.each do |violation|
          $stderr.printf(
            "%<criterion>s coverage has dropped by %<drop_percent>.2f%% since the last time (maximum allowed: %<max_drop>.2f%%).\n",
            criterion: violation.fetch(:criterion).capitalize,
            drop_percent: violation.fetch(:actual),
            max_drop: violation.fetch(:maximum)
          )
        end
      end

      def exit_code
        SimpleCov::ExitCodes::MAXIMUM_COVERAGE_DROP
      end

    private

      def violations
        @violations ||= SimpleCov::CoverageViolations.maximum_drop(@result, @maximum_coverage_drop)
      end
    end
  end
end
