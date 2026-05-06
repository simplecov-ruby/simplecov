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
        $stderr.printf(
          "%<criterion>s coverage (%<covered>.2f%%) is below the expected minimum coverage " \
          "(%<minimum_coverage>.2f%%).\n",
          covered: violation.fetch(:actual),
          minimum_coverage: violation.fetch(:expected),
          criterion: criterion.capitalize
        )
        report_worst_files(criterion)
      end

      def report_worst_files(criterion)
        worst = worst_files_for(criterion)
        return if worst.empty?

        warn "  Lowest-coverage files (#{criterion}):"
        worst.each do |path, percent|
          warn(format("    %<percent>6.2f%%  %<path>s", percent: percent, path: path))
        end
      end

      def worst_files_for(criterion)
        with_stats = @result.files.filter_map do |source_file|
          stats = source_file.coverage_statistics[criterion]
          [source_file.project_filename, stats.percent] if stats
        end
        with_stats.sort_by { |_path, percent| percent }.first(WORST_FILES_LIMIT)
      end
    end
  end
end
