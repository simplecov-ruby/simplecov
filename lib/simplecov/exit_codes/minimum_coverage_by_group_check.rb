# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    class MinimumCoverageByGroupCheck < Check
      def exit_code
        MINIMUM_COVERAGE
      end

    private

      def compute_violations
        CoverageViolations.minimum_by_group(result, thresholds)
      end

      def violation_lines(violation)
        [format(
          "%<criterion>s coverage by group (%<actual>s) is below the expected minimum coverage " \
          "(%<expected>.2f%%) in %<group_name>s.",
          criterion: violation.fetch(:criterion).capitalize,
          actual: Color.colorize_percent(violation.fetch(:actual)),
          expected: violation.fetch(:expected),
          group_name: violation.fetch(:group_name)
        )]
      end
    end
  end
end
