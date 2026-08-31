# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    class MaximumOverallCoverageCheck < Check
      def exit_code
        MAXIMUM_COVERAGE
      end

    private

      def compute_violations
        CoverageViolations.maximum_overall(result, thresholds)
      end

      def violation_lines(violation)
        [format(
          "%<criterion>s coverage (%<actual>s) is above the expected maximum coverage (%<expected>.2f%%). " \
          "Time to bump the threshold!",
          criterion: violation.fetch(:criterion).capitalize,
          actual: Color.colorize_percent(violation.fetch(:actual)),
          expected: violation.fetch(:expected)
        )]
      end
    end
  end
end
