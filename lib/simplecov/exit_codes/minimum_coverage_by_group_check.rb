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
        minimum_coverage_by_group.flat_map do |group_name, minimum_group_coverage|
          group = find_group(group_name)
          next [] unless group

          minimum_group_coverage.map do |criterion, expected_percent|
            actual_coverage = group.coverage_statistics.fetch(criterion)
            minimum_coverage_hash(group_name, criterion, expected_percent, SimpleCov.round_coverage(actual_coverage.percent))
          end
        end
      end

      def find_group(group_name)
        result.groups[group_name] || begin
          warn "minimum_coverage_by_group: no group named '#{group_name}' exists. Available groups: #{result.groups.keys.join(', ')}"
          nil
        end
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
