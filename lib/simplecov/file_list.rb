# frozen_string_literal: true

module SimpleCov
  # An array of SimpleCov SourceFile instances with additional collection helper
  # methods for calculating coverage across them etc.
  class FileList
    include Enumerable
    extend Forwardable

    def_delegators :@files,
                   # For Enumerable
                   :each,
                   # also delegating methods implemented in Enumerable as they have
                   # custom Array implementations which are presumably better/more
                   # resource efficient
                   :size, :map,
                   # surprisingly not in Enumerable
                   :empty?, :length,
                   # still act like we're kinda an array
                   :to_a, :to_ary

    def initialize(files)
      @files = files
    end

    def coverage
      {
        **line_coverage,
        **branch_coverage
      }
    end

    # Returns the count of lines that have coverage
    def covered_lines
      return 0.0 if empty?

      map { |f| f.covered_lines.count }.inject(:+)
    end

    # Returns the count of lines that have been missed
    def missed_lines
      return 0.0 if empty?

      map { |f| f.missed_lines.count }.inject(:+)
    end

    # Returns the count of lines that are not relevant for coverage
    def never_lines
      return 0.0 if empty?

      map { |f| f.never_lines.count }.inject(:+)
    end

    # Returns the count of skipped lines
    def skipped_lines
      return 0.0 if empty?

      map { |f| f.skipped_lines.count }.inject(:+)
    end

    # Computes the coverage based upon lines covered and lines missed for each file
    # Returns an array with all coverage percentages
    def covered_percentages
      map(&:covered_percent)
    end

    # Finds the least covered file and returns that file's name
    def least_covered_file
      min_by(&:covered_percent).filename
    end

    # Returns the overall amount of relevant lines of code across all files in this list
    def lines_of_code
      covered_lines + missed_lines
    end

    # Computes the coverage based upon lines covered and lines missed
    # @return [Float]
    def covered_percent
      percent(covered_lines, lines_of_code)
    end

    # Computes the strength (hits / line) based upon lines covered and lines missed
    # @return [Float]
    def covered_strength
      return 0.0 if empty? || lines_of_code.zero?

      Float(map { |f| f.covered_strength * f.lines_of_code }.inject(:+) / lines_of_code)
    end

    # Return total count of branches in all files
    def total_branches
      return 0 if empty?

      map { |file| file.total_branches.count }.inject(:+)
    end

    # Return total count of covered branches
    def covered_branches
      return 0 if empty?

      map { |file| file.covered_branches.count }.inject(:+)
    end

    # Return total count of covered branches
    def missed_branches
      return 0 if empty?

      map { |file| file.missed_branches.count }.inject(:+)
    end

    def branch_covered_percent
      percent(covered_branches, total_branches)
    end

  private

    def percent(covered, total)
      return 100.0 if empty? || total.zero?

      Float(covered * 100.0 / total)
    end

    def line_coverage
      {
        line: CoverageData.new(
          strength: covered_strength,
          covered: covered_lines,
          missed: missed_lines
        )
      }
    end

    def branch_coverage
      return nil unless SimpleCov.branch_coverage?

      {
        branch: CoverageData.new(
          covered: covered_branches,
          missed: missed_branches
        )
      }
    end
  end
end
