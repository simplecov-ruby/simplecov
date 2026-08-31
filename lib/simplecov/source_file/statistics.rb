# frozen_string_literal: true

module SimpleCov
  class SourceFile
    # Builds the `CoverageStatistics` triple for a SourceFile regardless of which
    # criteria were enabled during the run: disabled or empty criteria collapse to
    # 0/0/0 so downstream consumers don't have to special-case enable-state.
    class Statistics
      def initialize(source_file)
        @source_file = source_file
      end

      def call
        {
          **line_statistics,
          **branch_statistics,
          **method_statistics
        }
      end

    private

      def line_statistics
        {
          line: coverage_statistics(
            @source_file.covered_lines,
            @source_file.missed_lines,
            omitted: @source_file.never_lines.size
          )
        }
      end

      # Files added via track_files but never loaded have no branch or method data,
      # and report 0% instead of the empty-set default of 100% (#902). A file with
      # missed entries and none covered already computes to 0%, so only a file that
      # really has covered entries keeps its computed percentage.
      def branch_statistics
        sf = @source_file
        covered = sf.covered_branches
        missed = sf.missed_branches
        percent = 0.0 if sf.not_loaded? && covered.empty?

        {branch: coverage_statistics(covered, missed, percent: percent)}
      end

      def method_statistics
        sf = @source_file
        covered = sf.covered_methods
        missed = sf.missed_methods
        percent = 0.0 if sf.not_loaded? && covered.empty?

        {method: coverage_statistics(covered, missed, percent: percent)}
      end

      def coverage_statistics(covered, missed, omitted: 0, percent: nil)
        CoverageStatistics.new(
          total_strength: covered.sum { |item| item.coverage.to_i },
          covered: covered.size,
          missed: missed.size,
          omitted: omitted,
          percent: percent
        )
      end
    end
  end
end
