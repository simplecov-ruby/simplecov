# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    # Fails when the suite's total misses exceed the `maximum_missed`
    # cap for any criterion. The cap is an absolute burn-down number
    # ("12 uncovered lines left"), so the report speaks in counts, in
    # the criterion's own units.
    class MaximumMissedCheck < Check
      def exit_code
        MINIMUM_COVERAGE
      end

    private

      def compute_violations
        CoverageViolations.maximum_missed(result, thresholds)
      end

      def report_violation(violation)
        ExitCodes.print_error format(
          "Missed %<units>s (%<actual>d) exceed the configured maximum_missed (%<maximum>d).",
          units: UNITS.fetch(SimpleCov.coverage_statistics_key(violation.fetch(:criterion))),
          actual: violation.fetch(:actual),
          maximum: violation.fetch(:maximum)
        )
      end
    end
  end
end
