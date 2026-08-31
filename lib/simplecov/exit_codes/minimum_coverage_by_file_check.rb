# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    class MinimumCoverageByFileCheck < Check
      # `baseline:` exempts the file-and-criterion pairs it covers: those answer to
      # their own floor via `BaselineCheck` instead.
      def initialize(result, minimum_coverage_by_file, overrides = {}, baseline: nil)
        super(result, minimum_coverage_by_file)
        @overrides = overrides
        @baseline = baseline
      end

      def exit_code
        MINIMUM_COVERAGE
      end

    private

      def compute_violations
        CoverageViolations.minimum_by_file(result, thresholds, @overrides, baseline: @baseline)
      end

      def violation_lines(violation)
        [format(
          "%<criterion>s coverage by file (%<actual>s) is below the expected minimum coverage " \
          "(%<expected>.2f%%) in %<filename>s.",
          criterion: violation.fetch(:criterion).capitalize,
          actual: Color.colorize_percent(violation.fetch(:actual)),
          expected: violation.fetch(:expected),
          filename: violation.fetch(:project_filename)
        )]
      end
    end
  end
end
