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
                   :size, :map, :count,
                   # surprisingly not in Enumerable
                   :empty?, :length,
                   # still act like we're kinda an array
                   :to_a, :to_ary

    def initialize(files)
      @files = files
    end

    def coverage
      @coverage ||= compute_coverage
    end

    # Returns the count of lines that have coverage
    def covered_lines
      coverage[:line]&.covered
    end

    # Returns the count of lines that have been missed
    def missed_lines
      coverage[:line]&.missed
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
      coverage[:line]&.total
    end

    # Computes the coverage based upon lines covered and lines missed
    # @return [Float]
    def covered_percent
      coverage[:line]&.percent
    end

    # Computes the strength (hits / line) based upon lines covered and lines missed
    # @return [Float]
    def covered_strength
      coverage[:line]&.strength
    end

    # Return total count of branches in all files
    def total_branches
      coverage[:branch]&.total
    end

    # Return total count of covered branches
    def covered_branches
      coverage[:branch]&.covered
    end

    # Return total count of covered branches
    def missed_branches
      coverage[:branch]&.missed
    end

    def branch_covered_percent
      coverage[:branch]&.percent
    end

  private

    def compute_coverage
      total_coverage_statistics = @files.each_with_object(line: [], branch: []) do |file, together|
        together[:line] << file.coverage[:line]
        together[:branch] << file.coverage[:branch] if SimpleCov.branch_coverage?
      end

      coverage_statistics = {line: CoverageStatistics.from(total_coverage_statistics[:line])}
      coverage_statistics[:branch] = CoverageStatistics.from(total_coverage_statistics[:branch]) if SimpleCov.branch_coverage?
      coverage_statistics
    end
  end
end
