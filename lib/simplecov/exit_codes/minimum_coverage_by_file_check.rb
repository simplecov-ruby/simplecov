# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    class MinimumCoverageByFileCheck
      def initialize(result, minimum_coverage_by_file)
        @result = result
        @minimum_coverage_by_file = minimum_coverage_by_file
      end

      def failing?
        minimum_violations.any?
      end

      def report
        minimum_violations.each do |violation|
          $stderr.printf(
            "%<criterion>s coverage (%<covered>.2f%%) is below the expected minimum coverage (%<minimum_coverage>.2f%%).\n",
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

      attr_reader :result, :minimum_coverage_by_file

      def coverage_statistics_by_file
        @coverage_statistics_by_file ||=
          (res = result.coverage_statistics_by_file).each do |criteria, stats|
            res[criteria] = stats.map { |stat| SimpleCov.round_coverage(stat.percent) }
          end
      end

      def minimum_violations
        @minimum_violations ||=
          compute_minimum_violations.select do |achieved|
            achieved.fetch(:actual) < achieved.fetch(:minimum_expected)
          end
      end

      def compute_minimum_violations
        minimum_coverage_by_file.flat_map do |criterion, expected_percent|
          coverage_statistics_by_file[criterion].map do |actual_percent|
            {
              criterion: criterion,
              minimum_expected: expected_percent,
              actual: actual_percent
            }
          end
        end
      end
    end
  end
end
