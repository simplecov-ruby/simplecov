# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    # Runs every coverage check against the result and returns the exit
    # code from the first failing one (or SUCCESS if all pass).
    module ExitCodeHandling
      extend self

      def call(result, coverage_limits:)
        checks = coverage_checks(result, coverage_limits)

        failing_check = checks.find(&:failing?)
        if failing_check
          failing_check.report if SimpleCov.print_errors
          failing_check.exit_code
        else
          SUCCESS
        end
      end

      def coverage_checks(result, coverage_limits)
        [
          MinimumOverallCoverageCheck.new(result, coverage_limits.minimum_coverage),
          minimum_by_file_check(result, coverage_limits),
          BaselineCheck.new(result, coverage_limits.baseline),
          MinimumCoverageByGroupCheck.new(result, coverage_limits.minimum_coverage_by_group),
          MaximumOverallCoverageCheck.new(result, coverage_limits.maximum_coverage),
          MaximumCoverageDropCheck.new(result, coverage_limits.maximum_coverage_drop),
          MaximumMissedCheck.new(result, coverage_limits.maximum_missed),
          maximum_missed_per_file_check(result, coverage_limits)
        ]
      end

      # Split out for length alone; the baseline exempts the pairs it
      # covers from this check (see MinimumCoverageByFileCheck).
      def minimum_by_file_check(result, coverage_limits)
        MinimumCoverageByFileCheck.new(
          result, coverage_limits.minimum_coverage_by_file, coverage_limits.minimum_coverage_by_file_overrides,
          baseline: coverage_limits.baseline
        )
      end

      # Same baseline exemption as the per-file minimum (see
      # MaximumMissedPerFileCheck).
      def maximum_missed_per_file_check(result, coverage_limits)
        MaximumMissedPerFileCheck.new(
          result, coverage_limits.maximum_missed_per_file, coverage_limits.maximum_missed_per_file_overrides,
          baseline: coverage_limits.baseline
        )
      end
    end
  end
end
