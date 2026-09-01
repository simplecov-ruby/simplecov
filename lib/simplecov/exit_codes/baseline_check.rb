# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    # Fails when a file listed in the checked-in baseline drops below its own
    # floor on both axes: a lower percent than the floor records and more misses
    # than it allows. The second condition is the dampener that keeps an edit
    # with no coverage change from failing the run; a percent-only floor is
    # decided by the percent alone.
    class BaselineCheck < Check
      def initialize(result, baseline)
        super(result, nil)
        @baseline = baseline
      end

      def exit_code
        MINIMUM_COVERAGE
      end

      private

      def compute_violations
        CoverageViolations.baseline(result, @baseline)
      end

      def violation_lines(violation)
        message = format(
          "%<criterion>s coverage (%<actual>s) dropped below its baseline floor (%<expected>s%%) in %<filename>s",
          criterion: violation.fetch(:criterion).capitalize,
          actual: Color.colorize_percent(violation.fetch(:actual)),
          expected: violation.fetch(:expected),
          filename: violation.fetch(:project_filename)
        )
        ["#{message}#{missed_clause(violation)}."]
      end

      def missed_clause(violation)
        allowed = violation.fetch(:allowed_missed)
        return unless allowed

        units = UNITS.fetch(SimpleCov.coverage_statistics_key(violation.fetch(:criterion)))
        " (#{violation.fetch(:actual_missed)} uncovered #{units}, #{allowed} allowed)"
      end
    end
  end
end
