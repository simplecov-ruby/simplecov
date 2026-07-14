# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    # Fails when any individual file falls below the configured minimum
    # coverage for any criterion.
    class MinimumCoverageByFileCheck
      def initialize(result, minimum_coverage_by_file, overrides = {})
        @result = result
        @minimum_coverage_by_file = minimum_coverage_by_file
        @overrides = overrides
      end

      def failing?
        violations.any?
      end

      def report
        violations.each do |violation|
          ExitCodes.print_error format(
            "%<criterion>s coverage by file (%<actual>s) is below the expected minimum coverage " \
            "(%<expected>.2f%%) in %<filename>s.",
            criterion: violation.fetch(:criterion).capitalize,
            actual: SimpleCov::Color.colorize_percent(violation.fetch(:actual)),
            expected: violation.fetch(:expected),
            filename: violation.fetch(:project_filename)
          )
        end
      end

      def exit_code
        SimpleCov::ExitCodes::MINIMUM_COVERAGE
      end

    private

      def violations
        @violations ||= SimpleCov::CoverageViolations.minimum_by_file(
          @result, @minimum_coverage_by_file, @overrides
        )
      end
    end
  end
end
