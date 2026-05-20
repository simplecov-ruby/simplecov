# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    # Fails when the overall (project-wide) coverage for any criterion is
    # above the configured maximum. Pair with
    # `SimpleCov::ExitCodes::MinimumOverallCoverageCheck` (or use
    # `SimpleCov.expected_coverage`) to pin coverage to an exact value
    # and surface unexpected increases instead of silently absorbing them.
    class MaximumOverallCoverageCheck
      def initialize(result, maximum_coverage)
        @result = result
        @maximum_coverage = maximum_coverage
      end

      def failing?
        violations.any?
      end

      def report
        violations.each { |violation| report_violation(violation) }
      end

      def exit_code
        SimpleCov::ExitCodes::MAXIMUM_COVERAGE
      end

    private

      def violations
        @violations ||= SimpleCov::CoverageViolations.maximum_overall(@result, @maximum_coverage)
      end

      def report_violation(violation)
        warn format(
          "%<criterion>s coverage (%<actual>s) is above the expected maximum coverage (%<expected>.2f%%). " \
          "Time to bump the threshold!",
          criterion: violation.fetch(:criterion).capitalize,
          actual: SimpleCov::Color.colorize_percent(violation.fetch(:actual)),
          expected: violation.fetch(:expected)
        )
      end
    end
  end
end
