# frozen_string_literal: true

module SimpleCov
  class FileList
    include Enumerable
    extend Forwardable

    # Enumerable's own implementations are skipped where Array has a better
    # one, and `to_a` / `to_ary` keep this acting like the array it wraps.
    def_delegators :@files, :each, :size, :map, :count, :empty?, :length, :to_a, :to_ary

    def initialize(files)
      @files = files
    end

    # With no argument answers the `{line:, branch:, method:}` Hash, and with a
    # criterion symbol that one CoverageStatistics.
    def coverage_statistics(criterion = nil)
      stats = (@coverage_statistics ||= compute_coverage_statistics)
      criterion ? stats[criterion] : stats
    end

    def coverage_statistics_by_file
      @coverage_statistics_by_file ||= compute_coverage_statistics_by_file
    end

    def covered_lines
      coverage_statistics[:line]&.covered
    end

    def missed_lines
      coverage_statistics[:line]&.missed
    end

    def never_lines
      sum { |f| f.never_lines.size }
    end

    def skipped_lines
      sum { |f| f.skipped_lines.size }
    end

    def covered_percentages
      map(&:covered_percent)
    end

    # Nil for an empty list, such as a fully filtered result.
    def least_covered_file
      # `covered_percent` is nil only for an unmeasured criterion, and :line
      # is always measured, so the `|| 0.0` arm never fires at runtime; it
      # exists to satisfy min_by's Comparable requirement.
      min_by { |file| file.covered_percent || 0.0 }&.filename
    end

    def lines_of_code
      coverage_statistics[:line]&.total
    end

    # Nil if the criterion was not measured.
    def covered_percent(criterion = :line)
      coverage_statistics(criterion)&.percent
    end

    # The strength (average hits per relevant unit) for the given criterion.
    def covered_strength(criterion = :line)
      coverage_statistics(criterion)&.strength
    end

    def total_branches
      coverage_statistics[:branch]&.total
    end

    def covered_branches
      coverage_statistics[:branch]&.covered
    end

    def missed_branches
      coverage_statistics[:branch]&.missed
    end

    def branch_covered_percent
      coverage_statistics[:branch]&.percent
    end

    def total_methods
      coverage_statistics[:method]&.total
    end

    def covered_methods
      coverage_statistics[:method]&.covered
    end

    def missed_methods
      coverage_statistics[:method]&.missed
    end

    def method_covered_percent
      coverage_statistics[:method]&.percent
    end

    private

    # Seeded with one entry per criterion the user enabled, so an empty FileList
    # still yields the right shape. `SourceFile#coverage_statistics` always
    # reports all three criteria; FileList is the layer that filters to the
    # enabled set so disabled criteria don't surface in totals, JSON, or the
    # HTML report.
    def compute_coverage_statistics_by_file
      seed = enabled_criteria_for_reporting.to_h do |criterion|
        bucket = [] #: Array[CoverageStatistics]
        [criterion, bucket]
      end
      each_with_object(seed) do |file, together|
        file.coverage_statistics.each do |criterion, stats|
          together.fetch(criterion) << stats if together.key?(criterion)
        end
      end
    end

    def compute_coverage_statistics
      coverage_statistics_by_file.transform_values { |stats| CoverageStatistics.from(stats) }
    end

    # `:line` (or its `:oneshot_line` synonym) is reported when either criterion
    # is enabled; the JRuby-gated branch/method criteria are reported when they
    # pass their own engine-support check.
    def enabled_criteria_for_reporting
      criteria = [] #: Array[SimpleCov::criterion]
      criteria << :line if SimpleCov.line_coverage?
      criteria << :branch if SimpleCov.branch_coverage?
      criteria << :method if SimpleCov.method_coverage?
      criteria
    end
  end
end
