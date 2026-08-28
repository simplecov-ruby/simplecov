# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    # Fails when the overall (project-wide) coverage for any criterion is
    # above the configured maximum. Pair with
    # `SimpleCov::ExitCodes::MinimumOverallCoverageCheck` (or use
    # `SimpleCov.expected_coverage`) to pin coverage to an exact value
    # and surface unexpected increases instead of silently absorbing them.
    class MaximumOverallCoverageCheck < Check
      def exit_code
        MAXIMUM_COVERAGE
      end

    private

      def compute_violations
        CoverageViolations.maximum_overall(result, thresholds)
      end

      def report_violation(violation)
        ExitCodes.print_error format(
          "%<criterion>s coverage (%<actual>s) is above the expected maximum coverage (%<expected>.2f%%). " \
          "Time to bump the threshold!",
          criterion: violation.fetch(:criterion).capitalize,
          actual: Color.colorize_percent(violation.fetch(:actual)),
          expected: violation.fetch(:expected)
        )
      end
    end
  end
end
