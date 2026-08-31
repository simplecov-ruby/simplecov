# frozen_string_literal: true

module SimpleCov
  module CoverageViolations
    class << self
      def minimum_overall(result, thresholds)
        thresholds.filter_map do |criterion, expected|
          actual = percent_for(result, criterion) or next
          {criterion: criterion, expected: expected, actual: actual} if actual < expected
        end
      end

      # `percent_for` floors the actual percent to two decimal places, so an
      # actual of 95.4287 is treated as 95.42 and a maximum of 95.42 passes
      # (#187).
      def maximum_overall(result, thresholds)
        thresholds.filter_map do |criterion, expected|
          actual = percent_for(result, criterion) or next
          {criterion: criterion, expected: expected, actual: actual} if actual > expected
        end
      end

      # A file and criterion with a `baseline` floor is exempt here: the baseline
      # check holds it to its own floor instead, which is the fall-through the
      # ratchet workflow rests on (#1268).
      def minimum_by_file(result, defaults, overrides = {}, baseline: nil)
        result.files.flat_map do |file|
          effective = effective_per_file_thresholds(file, defaults, overrides)
          effective.filter_map do |criterion, expected|
            next if baseline&.covers?(file.project_filename, criterion)

            file_minimum_violation(file, criterion, expected)
          end
        end
      end

      # A baseline violation needs the file below its floor on both axes: a
      # percent under the floor's, and (when the floor records one) more misses
      # than it allows. The missed count is what keeps percent movement from
      # pure edits out of the answer.
      def baseline(result, baseline)
        return [] unless baseline

        result.files.flat_map do |file|
          entry = baseline.entry_for(file.project_filename)
          next [] unless entry

          entry.filter_map { |criterion, floor| baseline_violation(file, criterion, floor) }
        end
      end

      def maximum_missed(result, caps)
        caps.filter_map do |criterion, maximum|
          actual = missed_for(result, criterion) or next
          {criterion: criterion, maximum: maximum, actual: actual} if actual > maximum
        end
      end

      def maximum_missed_by_file(result, defaults, overrides = {}, baseline: nil)
        result.files.flat_map do |file|
          effective = effective_per_file_thresholds(file, defaults, overrides)
          effective.filter_map do |criterion, maximum|
            next if baseline&.covers?(file.project_filename, criterion)

            file_missed_cap_violation(file, criterion, maximum)
          end
        end
      end

      def minimum_by_group(result, thresholds)
        thresholds.flat_map do |group_name, minimums|
          group = lookup_group(result, group_name)
          none = [] # : Array[Hash[Symbol, untyped]]
          group ? group_minimum_violations(group_name, group, minimums) : none
        end
      end

      def maximum_drop(result, thresholds, last_run: nil, mode: SimpleCov.drop_baseline)
        baseline = drop_baseline_percents(mode, last_run)
        return [] unless baseline

        thresholds.filter_map do |criterion, maximum|
          actual = compute_drop(criterion, result, baseline)
          {criterion: criterion, maximum: maximum, actual: actual} if actual && actual > maximum
        end
      end

    private

      # Answers nil, and the caller silently skips, when the criterion was
      # configured but not measured by the runtime (`branch: 100` under the
      # "strict" profile on JRuby, say). The config-time
      # `raise_if_criterion_disabled` check catches the genuine mistake earlier.
      def percent_for(stats_source, criterion)
        stats = stats_source.coverage_statistics[SimpleCov.coverage_statistics_key(criterion)]
        round(stats.percent) if stats
      end

      def effective_per_file_thresholds(file, defaults, overrides)
        path = file.project_filename
        overrides.reduce(defaults) do |acc, (pattern, criterion_thresholds)|
          path_matches?(path, pattern) ? acc.merge(criterion_thresholds) : acc
        end
      end

      # `==` and `eql?` are indistinguishable for the String operands, so that
      # mutation is equivalent. The override examples pin every arm instead.
      # mutant:disable
      # mutant:disable
      def path_matches?(project_filename, pattern)
        return project_filename.match?(pattern) if pattern.is_a?(Regexp)
        return project_filename.start_with?(pattern) if pattern.end_with?("/")

        project_filename == pattern
      end

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

      # The misconfiguration notice is enforcement output, not a Ruby warning: it
      # must survive `-W0` and `Warning.warn` hooks, and honor `print_errors`.
      def lookup_group(result, group_name)
        group = result.groups[group_name]
        if group.nil? && SimpleCov.print_errors
          ExitCodes.print_error "minimum_coverage_by_group: no group named '#{group_name}' exists. " \
                                "Available groups: #{result.groups.keys.join(', ')}"
        end
        group
      end

      def drop_baseline_percents(mode, last_run)
        case mode
        when :median then median_baseline
        when :branch then branch_baseline
        else last_run_baseline(last_run || LastRun.read)
        end
      end

      # A hand-edited .last_run.json can carry any value type, and `LastRun.read`
      # only vouches for the top level being a Hash. `:covered_percent` is the
      # pre-criteria file format's spelling of the line percent.
      def last_run_baseline(last_run)
        return nil unless last_run.is_a?(Hash)

        previous = (_ = last_run)[:result]
        return nil unless previous.is_a?(Hash)

        previous = _ = previous
        {line: previous[:line] || previous[:covered_percent],
         branch: previous[:branch], method: previous[:method]}
      end

      def median_baseline
        totals = history_totals
        baseline = {} #: Hash[Symbol, untyped]
        %i[line branch method].each do |criterion|
          values = totals.map { |entry| entry[criterion.to_s] }.grep(Numeric)
          baseline[criterion] = median(values) unless values.empty?
        end
        baseline
      end

      def history_totals
        History.read.filter_map do |entry|
          entry.fetch("totals") if entry.is_a?(Hash) && entry["totals"].is_a?(Hash)
        end
      end

      def median(values)
        sorted = values.sort
        mid = sorted.length / 2
        sorted.length.odd? ? sorted.fetch(mid) : (sorted.fetch(mid - 1) + sorted.fetch(mid)).fdiv(2)
      end

      def branch_baseline
        branch, = History.git_info
        return nil unless branch

        entry = History.read.reverse_each.find { |candidate| branch_entry?(candidate, branch) }
        return nil unless entry

        totals = {} #: Hash[Symbol, untyped]
        entry.fetch("totals").each { |key, value| totals[key.to_sym] = value }
        totals
      end

      # `==` and `eql?` are indistinguishable for the String operands, so that
      # mutation is equivalent. The branch-baseline examples pin every clause.
      # mutant:disable
      # mutant:disable
      def branch_entry?(candidate, branch)
        candidate.is_a?(Hash) && candidate["branch"] == branch && candidate["totals"].is_a?(Hash)
      end

      def compute_drop(criterion, result, baseline)
        stats_key = SimpleCov.coverage_statistics_key(criterion)
        last_coverage_percent = baseline[stats_key]
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
end
