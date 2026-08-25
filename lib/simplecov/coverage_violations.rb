# frozen_string_literal: true

module SimpleCov
  # Computes coverage threshold violations for a given result. Shared by
  # the exit-code checks and the JSON formatter's `errors` section.
  #
  # Each method returns an array of violation hashes. All percents are
  # rounded via `SimpleCov.round_coverage` so downstream consumers don't
  # need to round again.
  # rubocop:disable Metrics/ModuleLength, Metrics/ClassLength -- one check
  # per threshold family, and each reads better next to the others than
  # split across files by size alone.
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
      #
      # `defaults` is the criterion-keyed Hash applied to every file.
      # `overrides` is an ordered Hash<pattern, criterion_thresholds> of per-path
      # overrides; for each file, defaults are merged with every matching override
      # (later wins per criterion, overrides win over defaults).
      # A file and criterion with a `baseline` floor is exempt here: the
      # baseline check holds it to its own floor instead, which is the
      # fall-through the ratchet workflow rests on (see #1268).
      def minimum_by_file(result, defaults, overrides = {}, baseline: nil)
        result.files.flat_map do |file|
          effective = effective_per_file_thresholds(file, defaults, overrides)
          effective.filter_map do |criterion, expected|
            next if baseline&.covers?(file.project_filename, criterion)

            file_minimum_violation(file, criterion, expected)
          end
        end
      end

      # @return [Array<Hash>] {:criterion, :expected, :allowed_missed, :actual,
      #   :actual_missed, :filename, :project_filename}
      #
      # A baseline violation needs the file below its floor on both axes:
      # a percent under the floor's, and (when the floor records one)
      # more misses than it allows. The missed count is the dampener
      # that keeps percent movement from pure edits out of the answer;
      # see `SimpleCov::Baseline`.
      def baseline(result, baseline)
        return [] unless baseline

        result.files.flat_map do |file|
          entry = baseline.entry_for(file.project_filename)
          next [] unless entry

          entry.filter_map { |criterion, floor| baseline_violation(file, criterion, floor) }
        end
      end

      # @return [Array<Hash>] {:criterion, :maximum, :actual} where both
      #   numbers are miss counts in the criterion's own units.
      def maximum_missed(result, caps)
        caps.filter_map do |criterion, maximum|
          actual = missed_for(result, criterion) or next
          {criterion: criterion, maximum: maximum, actual: actual} if actual > maximum
        end
      end

      # @return [Array<Hash>] {:criterion, :maximum, :actual, :filename,
      #   :project_filename}
      #
      # Same override-merge semantics as `minimum_by_file`, and the same
      # baseline exemption: a file and criterion with a floor answers to
      # the baseline check instead.
      def maximum_missed_by_file(result, defaults, overrides = {}, baseline: nil)
        result.files.flat_map do |file|
          effective = effective_per_file_thresholds(file, defaults, overrides)
          effective.filter_map do |criterion, maximum|
            next if baseline&.covers?(file.project_filename, criterion)

            file_missed_cap_violation(file, criterion, maximum)
          end
        end
      end

      # @return [Array<Hash>] {:group_name, :criterion, :expected, :actual}
      def minimum_by_group(result, thresholds)
        thresholds.flat_map do |group_name, minimums|
          group = lookup_group(result, group_name)
          none = [] # : Array[Hash[Symbol, untyped]]
          group ? group_minimum_violations(group_name, group, minimums) : none
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

      # Walk the overrides in declaration order, merging each one that matches
      # the file's project path into the running effective threshold (so the
      # most-specific or latest-declared override wins per criterion). Returns
      # the defaults Hash unchanged when nothing matches.
      def effective_per_file_thresholds(file, defaults, overrides)
        return defaults if overrides.empty?

        path = file.project_filename
        overrides.reduce(defaults) do |acc, (pattern, criterion_thresholds)|
          path_matches?(path, pattern) ? acc.merge(criterion_thresholds) : acc
        end
      end

      # Per-path matching for `minimum_coverage_by_file` overrides. Strings
      # ending in `/` are treated as directory prefixes; otherwise they must
      # match `project_filename` exactly. Regexps are tested via `match?`.
      # The configuration setter rejects anything other than String/Regexp,
      # so no dead `else` branch is needed here.
      def path_matches?(project_filename, pattern)
        return project_filename.match?(pattern) if pattern.is_a?(Regexp)
        return project_filename.start_with?(pattern) if pattern.end_with?("/")

        project_filename == pattern
      end

      # A criterion's missed count, nil (skip, like `percent_for`) when
      # the runtime didn't measure it.
      def missed_for(stats_source, criterion)
        stats = stats_source.coverage_statistics[SimpleCov.coverage_statistics_key(criterion)]
        stats&.missed
      end

      def file_missed_cap_violation(file, criterion, maximum)
        actual = missed_for(file, criterion) or return
        return unless actual > maximum

        {criterion: criterion, maximum: maximum, actual: actual,
         filename: file.filename, project_filename: file.project_filename}
      end

      def baseline_violation(file, criterion, floor)
        stats = file.coverage_statistics[SimpleCov.coverage_statistics_key(criterion)]
        return unless stats

        actual = round(stats.percent)
        return unless actual < floor.percent
        return if floor.missed && stats.missed <= floor.missed

        {criterion: criterion, expected: floor.percent, allowed_missed: floor.missed, actual: actual,
         actual_missed: stats.missed, filename: file.filename, project_filename: file.project_filename}
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

      # The misconfiguration notice is enforcement output, not a Ruby
      # warning: like every other enforcement message it must survive
      # `-W0` and `Warning.warn` hooks (see ExitCodes.print_error) and
      # honor the `print_errors` opt-out.
      def lookup_group(result, group_name)
        group = result.groups[group_name]
        if group.nil? && SimpleCov.print_errors
          ExitCodes.print_error "minimum_coverage_by_group: no group named '#{group_name}' exists. " \
                                "Available groups: #{result.groups.keys.join(', ')}"
        end
        group
      end

      def compute_drop(criterion, result, last_run)
        stats_key = SimpleCov.coverage_statistics_key(criterion)
        last_coverage_percent = last_run.dig(:result, stats_key)
        if last_coverage_percent.nil? && stats_key == :line
          last_coverage_percent = last_run.dig(:result, :covered_percent)
        end
        # A hand-edited .last_run.json can carry any value type, and
        # LastRun.read only vouches for the top level being a Hash.
        # Treat a non-numeric percent like a missing one instead of
        # raising out of the at_exit hook.
        return unless last_coverage_percent.is_a?(Numeric)

        current = percent_for(result, criterion) or return
        (last_coverage_percent - current).floor(10)
      end

      def round(percent)
        SimpleCov.round_coverage(percent)
      end
    end
  end
  # rubocop:enable Metrics/ModuleLength, Metrics/ClassLength
end
