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
          actual = round(result.coverage_statistics.fetch(criterion).percent)
          {criterion: criterion, expected: expected, actual: actual} if actual < expected
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

      def file_minimum_violation(file, criterion, expected)
        actual = round(file.coverage_statistics.fetch(criterion).percent)
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
          actual = round(group.coverage_statistics.fetch(criterion).percent)
          {group_name: group_name, criterion: criterion, expected: expected, actual: actual} if actual < expected
        end
      end

      def lookup_group(result, group_name)
        group = result.groups[group_name]
        warn "minimum_coverage_by_group: no group named '#{group_name}' exists. Available groups: #{result.groups.keys.join(', ')}" unless group
        group
      end

      def compute_drop(criterion, result, last_run)
        last_coverage_percent = last_run.dig(:result, criterion)
        last_coverage_percent ||= last_run.dig(:result, :covered_percent) if criterion == :line
        return unless last_coverage_percent

        current = round(result.coverage_statistics.fetch(criterion).percent)
        (last_coverage_percent - current).floor(10)
      end

      def round(percent)
        SimpleCov.round_coverage(percent)
      end
    end
  end
end
