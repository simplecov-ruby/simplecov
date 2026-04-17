# frozen_string_literal: true

module SimpleCov
  module ExitCodes
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
          $stderr.printf(
            "%<criterion>s coverage by group (%<covered>.2f%%) is below the expected minimum coverage (%<minimum_coverage>.2f%%) in %<group_name>s.\n",
            group_name: violation.fetch(:group_name),
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
        @violations ||= SimpleCov::CoverageViolations.minimum_by_group(@result, @minimum_coverage_by_group)
      end
    end
  end
end
