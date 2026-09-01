# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    class MaximumMissedCheck < Check
      def exit_code
        MINIMUM_COVERAGE
      end

      private

      def compute_violations
        CoverageViolations.maximum_missed(result, thresholds)
      end

      def violation_lines(violation)
        [format(
          "Missed %<units>s (%<actual>d) exceed the configured maximum_missed (%<maximum>d).",
          units: UNITS.fetch(SimpleCov.coverage_statistics_key(violation.fetch(:criterion))),
          actual: violation.fetch(:actual),
          maximum: violation.fetch(:maximum)
        )]
      end
    end
  end
end
