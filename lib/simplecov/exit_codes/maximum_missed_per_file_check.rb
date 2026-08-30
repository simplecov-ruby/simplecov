# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    # Fails when any single file carries more misses than the
    # `maximum_missed_per_file` cap for any criterion. Unlike a percent
    # minimum, which flatters big files, the cap holds every file to the
    # same absolute budget. Files with a baseline entry answer to their
    # own floor instead (see BaselineCheck).
    class MaximumMissedPerFileCheck < Check
      def initialize(result, maximum_missed_per_file, overrides = {}, baseline: nil)
        super(result, maximum_missed_per_file)
        @overrides = overrides
        @baseline = baseline
      end

      def exit_code
        MINIMUM_COVERAGE
      end

    private

      def compute_violations
        CoverageViolations.maximum_missed_by_file(result, thresholds, @overrides, baseline: @baseline)
      end

      def violation_lines(violation)
        [format(
          "Missed %<units>s (%<actual>d) exceed the configured maximum_missed_per_file (%<maximum>d) " \
          "in %<filename>s.",
          units: UNITS.fetch(SimpleCov.coverage_statistics_key(violation.fetch(:criterion))),
          actual: violation.fetch(:actual),
          maximum: violation.fetch(:maximum),
          filename: violation.fetch(:project_filename)
        )]
      end
    end
  end
end
