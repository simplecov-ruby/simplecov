# frozen_string_literal: true

module SimpleCov
  class SourceFile
    # Builds the `CoverageStatistics` triple (`:line`, `:branch`, `:method`)
    # for a SourceFile, regardless of which criteria were actually enabled
    # during the run — disabled or empty criteria collapse to 0/0/0 so
    # downstream consumers don't have to special-case enable-state.
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
        sf = @source_file
        {
          line: CoverageStatistics.new(
            total_strength: sf.lines.sum { |line| line.coverage.to_i },
            covered: sf.covered_lines.size,
            missed: sf.missed_lines.size,
            omitted: sf.never_lines.size
          )
        }
      end

      def branch_statistics
        sf = @source_file
        # Files added via track_files but never loaded/required have no
        # branch data. Report 0% instead of misleading 100% (see #902).
        if sf.not_loaded? && sf.covered_branches.empty? && sf.missed_branches.empty?
          return {branch: CoverageStatistics.new(covered: 0, missed: 0, percent: 0.0)}
        end

        {branch: CoverageStatistics.new(covered: sf.covered_branches.size, missed: sf.missed_branches.size)}
      end

      def method_statistics
        sf = @source_file
        if sf.not_loaded? && sf.covered_methods.empty? && sf.missed_methods.empty?
          return {method: CoverageStatistics.new(covered: 0, missed: 0, percent: 0.0)}
        end

        {method: CoverageStatistics.new(covered: sf.covered_methods.size, missed: sf.missed_methods.size)}
      end
    end
  end
end
