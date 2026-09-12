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

      def branch_statistics
        sf = @source_file
        covered = sf.covered_branches
        missed = sf.missed_branches
        percent = 0.0 if covered.empty? && unaccounted?(sf, "branches")

        {branch: coverage_statistics(covered, missed, percent: percent)}
      end

      def method_statistics
        sf = @source_file
        covered = sf.covered_methods
        missed = sf.missed_methods
        percent = 0.0 if covered.empty? && unaccounted?(sf, "methods")

        {method: coverage_statistics(covered, missed, percent: percent)}
      end

      # A file tracked but never loaded once carried no branch or method tuples
      # at all, so an empty set meant "nobody knows", and answering the
      # empty-set default of 100% overstated it (#902). Simulation now
      # synthesizes those tuples statically, so a file carrying a table at all,
      # empty or not, has been accounted for: it has no branches, or a
      # directive skipped the ones it has, and it is as covered as a loaded
      # file with none. Only a file carrying no table for the criterion is
      # still unaccounted for. A file with missed entries and none covered
      # already computes to 0% either way, so only one that really has covered
      # entries keeps its computed percentage.
      def unaccounted?(source_file, table)
        source_file.not_loaded? && source_file.coverage_data[table].nil?
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
