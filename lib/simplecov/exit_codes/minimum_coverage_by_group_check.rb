# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    # Fails when any configured group falls below its minimum coverage
    # threshold for any criterion.
    class MinimumCoverageByGroupCheck
      def initialize(result, minimum_coverage_by_group)
        @result = result
        @minimum_coverage_by_group = minimum_coverage_by_group
      end

      def failing?
        violations.any?
      end

      def report
        violations.each do |violation|
          ExitCodes.print_error format(
            "%<criterion>s coverage by group (%<actual>s) is below the expected minimum coverage " \
            "(%<expected>.2f%%) in %<group_name>s.",
            criterion: violation.fetch(:criterion).capitalize,
            actual: SimpleCov::Color.colorize_percent(violation.fetch(:actual)),
            expected: violation.fetch(:expected),
            group_name: violation.fetch(:group_name)
          )
        end
      end

      def exit_code
        SimpleCov::ExitCodes::MINIMUM_COVERAGE
      end

    private

      def violations
        @violations ||= SimpleCov::CoverageViolations.minimum_by_group(@result, @minimum_coverage_by_group)
      end
    end
  end
end
