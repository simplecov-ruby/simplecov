# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    class MinimumCoverageByFileCheck
      def initialize(result, minimum_coverage_by_file)
        @result = result
        @minimum_coverage_by_file = minimum_coverage_by_file
      end

      def failing?
        covered_percentages.any? { |p| p < minimum_coverage_by_file }
      end

      def report
        $stderr.printf(
          "File (%<file>s) is only (%<least_covered_percentage>.2f%%) covered. This is below the expected minimum coverage per file of (%<min_coverage>.2f%%).\n",
          file: result.least_covered_file,
          least_covered_percentage: covered_percentages.min,
          min_coverage: minimum_coverage_by_file
        )
      end

      def exit_code
        SimpleCov::ExitCodes::MINIMUM_COVERAGE
      end

    private

      attr_reader :result, :minimum_coverage_by_file

      def covered_percentages
        @covered_percentages ||=
          result.covered_percentages.map { |percentage| SimpleCov.round_coverage(percentage) }
      end
    end
  end
end
