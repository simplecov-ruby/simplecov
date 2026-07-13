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

    # The per-criterion coverage statistics across all files. With no argument
    # returns the `{line:, branch:, method:}` Hash; pass a criterion symbol
    # (`:line` / `:branch` / `:method`) to get that one CoverageStatistics.
    def coverage_statistics(criterion = nil)
      stats = (@coverage_statistics ||= compute_coverage_statistics)
      criterion ? stats[criterion] : stats
    end

    def coverage_statistics_by_file
      @coverage_statistics_by_file ||= compute_coverage_statistics_by_file
    end

    # Returns the count of lines that have coverage
    def covered_lines
      coverage_statistics[:line]&.covered
    end

    # Returns the count of lines that have been missed
    def missed_lines
      coverage_statistics[:line]&.missed
    end

    # Returns the count of lines that are not relevant for coverage
    def never_lines
      return 0.0 if empty?

      sum { |f| f.never_lines.size }
    end

    # Returns the count of skipped lines
    def skipped_lines
      return 0.0 if empty?

      sum { |f| f.skipped_lines.size }
    end

    # Computes the coverage based upon lines covered and lines missed for each file
    # Returns an array with all coverage percentages
    def covered_percentages
      map(&:covered_percent)
    end

    # Finds the least covered file and returns that file's name
    def least_covered_file
      # `covered_percent` is nil only for an unmeasured criterion, and :line
      # is always measured, so the `|| 0.0` arm never fires at runtime; it
      # (and the cast) exist to satisfy min_by's Comparable requirement.
      least_covered = min_by { |file| file.covered_percent || 0.0 }
      (_ = least_covered).filename
    end

    # Returns the overall amount of relevant lines of code across all files in this list
    def lines_of_code
      coverage_statistics[:line]&.total
    end

    # The coverage across all files in percent, for the given criterion (line
    # by default). Returns nil if the criterion was not measured.
    # @return [Float, nil]
    def covered_percent(criterion = :line)
      coverage_statistics(criterion)&.percent
    end

    # The strength (average hits per relevant unit) for the given criterion
    # (line by default).
    # @return [Float, nil]
    def covered_strength(criterion = :line)
      coverage_statistics(criterion)&.strength
    end

    # Return total count of branches in all files
    def total_branches
      coverage_statistics[:branch]&.total
    end

    # Return total count of covered branches
    def covered_branches
      coverage_statistics[:branch]&.covered
    end

    # Return total count of covered branches
    def missed_branches
      coverage_statistics[:branch]&.missed
    end

    def branch_covered_percent
      coverage_statistics[:branch]&.percent
    end

    # Return total count of methods in all files
    def total_methods
      coverage_statistics[:method]&.total
    end

    # Return total count of covered methods
    def covered_methods
      coverage_statistics[:method]&.covered
    end

    # Return total count of missed methods
    def missed_methods
      coverage_statistics[:method]&.missed
    end

    def method_covered_percent
      coverage_statistics[:method]&.percent
    end

  private

    # Seed the result hash with one entry per criterion the user
    # enabled — so an empty FileList (e.g. a group with no files) still
    # yields the right shape — then fold each file's stats into the
    # matching bucket. `SourceFile#coverage_statistics` always reports
    # all three criteria; FileList is the layer that filters to the
    # enabled set so disabled criteria don't surface in totals, JSON,
    # or the HTML report.
    def compute_coverage_statistics_by_file
      seed = enabled_criteria_for_reporting.to_h do |criterion|
        bucket = [] #: Array[CoverageStatistics]
        [criterion, bucket]
      end
      @files.each_with_object(seed) do |file, together|
        file.coverage_statistics.each do |criterion, stats|
          together[criterion] << stats if together.key?(criterion)
        end
      end
    end

    def compute_coverage_statistics
      coverage_statistics_by_file.transform_values { |stats| CoverageStatistics.from(stats) }
    end

    # `:line` (or its `:oneshot_line` synonym) is reported when either
    # criterion is enabled; the JRuby-gated branch/method criteria are
    # reported when they pass their own engine-support check.
    def enabled_criteria_for_reporting
      criteria = [] #: Array[SimpleCov::criterion]
      criteria << :line   if SimpleCov.coverage_criterion_enabled?(:line) ||
                             SimpleCov.coverage_criterion_enabled?(:oneshot_line)
      criteria << :branch if SimpleCov.branch_coverage?
      criteria << :method if SimpleCov.method_coverage?
      criteria
    end
  end
end
