# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    # Runs every coverage check against the result and returns the exit
    # code from the first failing one (or SUCCESS if all pass).
    module ExitCodeHandling
    module_function

      def call(result, coverage_limits:)
        checks = coverage_checks(result, coverage_limits)

        failing_check = checks.find(&:failing?)
        if failing_check
          failing_check.report if SimpleCov.print_errors
          failing_check.exit_code
        else
          SimpleCov::ExitCodes::SUCCESS
        end
      end

      def coverage_checks(result, coverage_limits)
        [
          MinimumOverallCoverageCheck.new(result, coverage_limits.minimum_coverage),
          MinimumCoverageByFileCheck.new(
            result, coverage_limits.minimum_coverage_by_file, coverage_limits.minimum_coverage_by_file_overrides
          ),
          MinimumCoverageByGroupCheck.new(result, coverage_limits.minimum_coverage_by_group),
          MaximumOverallCoverageCheck.new(result, coverage_limits.maximum_coverage),
          MaximumCoverageDropCheck.new(result, coverage_limits.maximum_coverage_drop)
        ]
      end
    end
  end
end
