# frozen_string_literal: true

module SimpleCov
  # Computes coverage threshold violations for a given result. Shared by
  # the exit-code checks and the JSON formatter's `errors` section.
  #
  # Each method returns an array of violation hashes. All percents are
  # rounded via `SimpleCov.round_coverage` so downstream consumers don't
  # need to round again.
  module CoverageViolations
    class << self
      # @return [Array<Hash>] {:criterion, :expected, :actual}
      def minimum_overall(result, thresholds)
        thresholds.filter_map do |criterion, expected|
          actual = percent_for(result, criterion) or next
          {criterion: criterion, expected: expected, actual: actual} if actual < expected
        end
      end

      # @return [Array<Hash>] {:criterion, :expected, :actual}
      # Tolerance: `percent_for` floors the actual percent to two decimal
      # places (matching the existing minimum-coverage behavior), so an
      # actual of e.g. 95.4287 is treated as 95.42 — meaning a maximum of
      # 95.42 still passes. See issue #187 for the rationale.
      def maximum_overall(result, thresholds)
        thresholds.filter_map do |criterion, expected|
          actual = percent_for(result, criterion) or next
          {criterion: criterion, expected: expected, actual: actual} if actual > expected
        end
      end

      # @return [Array<Hash>] {:criterion, :expected, :actual, :filename, :project_filename}
      def minimum_by_file(result, thresholds)
        thresholds.flat_map do |criterion, expected|
          result.files.filter_map { |file| file_minimum_violation(file, criterion, expected) }
        end
      end

      # @return [Array<Hash>] {:group_name, :criterion, :expected, :actual}
      def minimum_by_group(result, thresholds)
        thresholds.flat_map do |group_name, minimums|
          group = lookup_group(result, group_name)
          group ? group_minimum_violations(group_name, group, minimums) : []
        end
      end

      # @return [Array<Hash>] {:criterion, :maximum, :actual} where `actual`
      #   is the observed drop (in percentage points) vs. the last run.
      def maximum_drop(result, thresholds, last_run: SimpleCov::LastRun.read)
        return [] unless last_run

        thresholds.filter_map do |criterion, maximum|
          actual = compute_drop(criterion, result, last_run)
          {criterion: criterion, maximum: maximum, actual: actual} if actual && actual > maximum
        end
      end

    private

      # Look up a criterion's percent on any coverage_statistics-bearing
      # object (Result, SourceFile, FileList). Returns nil — and the
      # caller silently skips — when the criterion was configured but not
      # actually measured by the runtime (e.g. `minimum_coverage branch:
      # 100` under the "strict" profile on JRuby, where the Coverage
      # module doesn't emit branch data). The config-time
      # `raise_if_criterion_disabled` check still catches the genuine
      # "forgot to enable the criterion" mistake before we ever get here.
      def percent_for(stats_source, criterion)
        stats = stats_source.coverage_statistics[SimpleCov.coverage_statistics_key(criterion)]
        round(stats.percent) if stats
      end

      def file_minimum_violation(file, criterion, expected)
        actual = percent_for(file, criterion) or return
        return unless actual < expected

        {
          criterion: criterion,
          expected: expected,
          actual: actual,
          filename: file.filename,
          project_filename: file.project_filename
        }
      end

      def group_minimum_violations(group_name, group, minimums)
        minimums.filter_map do |criterion, expected|
          actual = percent_for(group, criterion) or next
          {group_name: group_name, criterion: criterion, expected: expected, actual: actual} if actual < expected
        end
      end

      def lookup_group(result, group_name)
        group = result.groups[group_name]
        unless group
          warn "minimum_coverage_by_group: no group named '#{group_name}' exists. " \
               "Available groups: #{result.groups.keys.join(', ')}"
        end
        group
      end

      def compute_drop(criterion, result, last_run)
        stats_key = SimpleCov.coverage_statistics_key(criterion)
        last_coverage_percent = last_run.dig(:result, stats_key)
        last_coverage_percent ||= last_run.dig(:result, :covered_percent) if stats_key == :line
        return unless last_coverage_percent

        current = percent_for(result, criterion) or return
        (last_coverage_percent - current).floor(10)
      end

      def round(percent)
        SimpleCov.round_coverage(percent)
      end
    end
  end
end
