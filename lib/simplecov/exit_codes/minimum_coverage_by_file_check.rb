# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    # Fails when any individual file falls below the configured minimum
    # coverage for any criterion.
    class MinimumCoverageByFileCheck < Check
      def initialize(result, minimum_coverage_by_file, overrides = {})
        super(result, minimum_coverage_by_file)
        @overrides = overrides
      end

      def exit_code
        SimpleCov::ExitCodes::MINIMUM_COVERAGE
      end

    private

      def compute_violations
        SimpleCov::CoverageViolations.minimum_by_file(result, thresholds, @overrides)
      end

      def report_violation(violation)
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
  end
end
