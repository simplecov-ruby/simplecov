# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    class MinimumCoverageByGroupCheck
      def initialize(result, minimum_coverage_by_group)
        @result = result
        @minimum_coverage_by_group = minimum_coverage_by_group
      end

      def failing?
        minimum_violations.any?
      end

      def report
        minimum_violations.each do |violation|
          $stderr.printf(
            "%<criterion>s coverage by group %<group_name>s (%<covered>.2f%%) is below the expected minimum coverage (%<minimum_coverage>.2f%%).\n",
            group_name: violation.fetch(:group_name),
            covered: SimpleCov.round_coverage(violation.fetch(:actual)),
            minimum_coverage: violation.fetch(:minimum_expected),
            criterion: violation.fetch(:criterion).capitalize
          )
        end
      end

      def exit_code
        SimpleCov::ExitCodes::MINIMUM_COVERAGE
      end

    private

      attr_reader :result, :minimum_coverage_by_group

      def minimum_violations
        @minimum_violations ||=
          compute_minimum_coverage_data.select do |achieved|
            achieved.fetch(:actual) < achieved.fetch(:minimum_expected)
          end
      end

      def compute_minimum_coverage_data
        minimum_coverage_data = []

        minimum_coverage_by_group.each do |group_name, minimum_group_coverage|
          minimum_group_coverage.each do |criterion, expected_percent|
            actual_coverage = result.groups.fetch(group_name).coverage_statistics.fetch(criterion)
            minimum_coverage_data << minimum_coverage_hash(group_name, criterion, expected_percent, SimpleCov.round_coverage(actual_coverage.percent))
          end
        end

        minimum_coverage_data
      end

      def minimum_coverage_hash(group_name, criterion, minimum_expected, actual)
        {
          group_name: group_name,
          criterion: criterion,
          minimum_expected: minimum_expected,
          actual: actual
        }
      end
    end
  end
end
