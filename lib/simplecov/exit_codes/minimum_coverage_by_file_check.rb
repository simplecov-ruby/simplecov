# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    class MinimumCoverageByFileCheck
      def initialize(result, minimum_coverage_by_file)
        @result = result
        @minimum_coverage_by_file = minimum_coverage_by_file
      end

      def failing?
        violations.any?
      end

      def report
        violations.each do |violation|
          $stderr.printf(
            "%<criterion>s coverage by file (%<covered>.2f%%) is below the expected minimum coverage (%<minimum_coverage>.2f%%) in %<filename>s.\n",
            covered: violation.fetch(:actual),
            minimum_coverage: violation.fetch(:expected),
            criterion: violation.fetch(:criterion).capitalize,
            filename: violation.fetch(:project_filename)
          )
        end
      end

      def exit_code
        SimpleCov::ExitCodes::MINIMUM_COVERAGE
      end

    private

      def violations
        @violations ||= SimpleCov::CoverageViolations.minimum_by_file(@result, @minimum_coverage_by_file)
      end
    end
  end
end
