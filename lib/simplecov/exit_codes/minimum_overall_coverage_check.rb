# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    class MinimumOverallCoverageCheck
      def initialize(result, minimum_coverage)
        @result = result
        @minimum_coverage = minimum_coverage
      end

      def failing?
        violations.any?
      end

      def report
        violations.each do |violation|
          $stderr.printf(
            "%<criterion>s coverage (%<covered>.2f%%) is below the expected minimum coverage (%<minimum_coverage>.2f%%).\n",
            covered: violation.fetch(:actual),
            minimum_coverage: violation.fetch(:expected),
            criterion: violation.fetch(:criterion).capitalize
          )
        end
      end

      def exit_code
        SimpleCov::ExitCodes::MINIMUM_COVERAGE
      end

    private

      def violations
        @violations ||= SimpleCov::CoverageViolations.minimum_overall(@result, @minimum_coverage)
      end
    end
  end
end
