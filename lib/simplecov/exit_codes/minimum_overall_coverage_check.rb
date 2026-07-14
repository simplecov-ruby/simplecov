# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    # Fails when the overall (project-wide) coverage for any criterion is
    # below the configured minimum.
    class MinimumOverallCoverageCheck
      def initialize(result, minimum_coverage)
        @result = result
        @minimum_coverage = minimum_coverage
      end

      def failing?
        violations.any?
      end

      def report
        violations.each { |violation| report_violation(violation) }
      end

      def exit_code
        SimpleCov::ExitCodes::MINIMUM_COVERAGE
      end

    private

      WORST_FILES_LIMIT = 5
      private_constant :WORST_FILES_LIMIT

      def violations
        @violations ||= SimpleCov::CoverageViolations.minimum_overall(@result, @minimum_coverage)
      end

      def report_violation(violation)
        criterion = violation.fetch(:criterion)
        actual = violation.fetch(:actual)
        ExitCodes.print_error format(
          "%<criterion>s coverage (%<actual>s) is below the expected minimum coverage (%<expected>.2f%%).",
          criterion: criterion.capitalize,
          actual: SimpleCov::Color.colorize_percent(actual),
          expected: violation.fetch(:expected)
        )
        report_worst_files(criterion)
      end

      def report_worst_files(criterion)
        worst = worst_files_for(criterion)
        return if worst.empty?

        ExitCodes.print_error "  Lowest-coverage files (#{criterion}):"
        worst.each do |path, percent|
          ExitCodes.print_error format(
            "    %<percent>s  %<path>s",
            percent: SimpleCov::Color.colorize_percent(percent, format("%6.2f%%", percent)),
            path: path
          )
        end
      end

      def worst_files_for(criterion)
        stats_key = SimpleCov.coverage_statistics_key(criterion)
        with_stats = @result.files.filter_map do |source_file|
          stats = source_file.coverage_statistics[stats_key]
          [source_file.project_filename, stats.percent] if stats
        end
        with_stats.sort_by { |_path, percent| percent }.first(WORST_FILES_LIMIT)
      end
    end
  end
end
