# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    class MinimumOverallCoverageCheck < Check
      def exit_code
        MINIMUM_COVERAGE
      end

      private

      WORST_FILES_LIMIT = 5
      private_constant :WORST_FILES_LIMIT

      def compute_violations
        CoverageViolations.minimum_overall(result, thresholds)
      end

      def violation_lines(violation)
        criterion = violation.fetch(:criterion)
        headline = format(
          "%<criterion>s coverage (%<actual>s) is below the expected minimum coverage (%<expected>.2f%%).",
          criterion: criterion.capitalize,
          actual: Color.colorize_percent(violation.fetch(:actual)),
          expected: violation.fetch(:expected)
        )
        [headline, *worst_files_lines(criterion)]
      end

      def worst_files_lines(criterion)
        worst = worst_files_for(criterion)
        return [] if worst.empty?

        ["  Lowest-coverage files (#{criterion}):"] + worst.map do |path, percent|
          format(
            "    %<percent>s  %<path>s",
            percent: Color.colorize_percent(percent, format("%6.2f%%", percent)),
            path: path
          )
        end
      end

      # The list is a hint at where to add tests, so a fully covered file has no
      # business on it: without the filter, files at 100% padded the list out to
      # its five entries (#1286).
      def worst_files_for(criterion)
        stats_key = SimpleCov.coverage_statistics_key(criterion)
        with_stats = result.files.filter_map do |source_file|
          stats = source_file.coverage_statistics[stats_key]
          [source_file.project_filename, stats.percent] if stats && stats.percent < 100
        end
        with_stats.sort_by { |_path, percent| percent }.first(WORST_FILES_LIMIT)
      end
    end
  end
end
