# frozen_string_literal: true

# Result-building façade: turns the raw `Coverage.result` hash into a
# `SimpleCov::Result`, applies filters and groups, drives merging
# across test suites via `SimpleCov::ResultMerger`, and exposes the
# `collate` entry point for stitching disparate resultsets together.
module SimpleCov
  class << self
    #
    # Collate a series of SimpleCov result files into a single SimpleCov output.
    #
    # See README for usage. By default `collate` ignores the merge_timeout
    # so all results in all files specified will be merged. Pass
    # `ignore_timeout: false` to honor it.
    #
    def collate(result_filenames, profile = nil, ignore_timeout: true, &)
      raise ArgumentError, "There are no reports to be merged" if result_filenames.empty?

      initial_setup(profile, &)

      # Use the ResultMerger to produce a single, merged result, ready to use.
      @result = ResultMerger.merge_and_store(*result_filenames, ignore_timeout: ignore_timeout)

      @collating_result = true
      run_exit_tasks!
    ensure
      @collating_result = false
    end

    #
    # Returns the result for the current coverage run, merging it across test suites
    # from cache using SimpleCov::ResultMerger if use_merging is activated (default)
    #
    def result
      return @result if result?

      use_merging = merging

      # Collect our coverage result. When merging is off there is no merge
      # step, so this per-process result is the final one and reports any
      # dropped source files; otherwise the merged result does the reporting.
      process_coverage_result(report: !use_merging) if defined?(Coverage) && Coverage.running?

      # If we're using merging of results, store the current result
      # first (if there is one), then merge the results and return those
      if use_merging
        SimpleCov::ResultMerger.store_result(@result) if result?
        return @result unless finalize_merge?

        wait_for_other_processes
        @result = SimpleCov::ResultMerger.merged_result
      end

      @result
    end

    # Returns nil if the result has not been computed, otherwise the result.
    def result?
      defined?(@result) && @result
    end

    # @api private — true while `SimpleCov.collate` is running its finalizer.
    def collating_result?
      defined?(@collating_result) && @collating_result
    end

    # Applies the configured filters to the given array of SimpleCov::SourceFile items
    def filtered(files)
      result = files.to_a.dup
      filters.each do |filter|
        result = result.reject { |source_file| filter.matches?(source_file) }
      end
      SimpleCov::FileList.new result
    end

    # Bin the given source files by group filter. `groups:` defaults to
    # `SimpleCov.groups`; pass a Hash explicitly to bin against a
    # different group config (e.g., the snapshot a Result captured at
    # construction). Files matched by no group fall into the implicit
    # "Ungrouped" bucket.
    def grouped(files, groups: SimpleCov.groups)
      return {} if groups.empty?

      grouped = groups.transform_values do |filter|
        SimpleCov::FileList.new(files.select { |source_file| filter.matches?(source_file) })
      end

      in_group  = grouped_file_set(grouped)
      ungrouped = files.reject { |source_file| in_group.include?(source_file) }
      grouped["Ungrouped"] = SimpleCov::FileList.new(ungrouped) if ungrouped.any?

      grouped
    end

    # Applies the profile of given name on SimpleCov configuration
    def load_profile(name)
      profiles.load(name)
    end

    # Clear out the previously cached .result. Primarily useful in testing.
    def clear_result
      @result = nil
    end

    # @api private — persist the per-criterion coverage percentages
    # rounded down (see #679) so the next run can compute drift.
    def write_last_run(result)
      SimpleCov::LastRun.write(
        result: result.coverage_statistics.transform_values { |stats| round_coverage(stats.percent) }
      )
    end

    # @api private — round down to two decimals to be extra strict.
    def round_coverage(coverage)
      coverage.floor(2)
    end

  private

    def initial_setup(profile, &block)
      load_profile(profile) if profile
      configure(&block) if block
    end

    def grouped_file_set(grouped)
      grouped.values.each_with_object(Set.new) { |file_list, set| set.merge(file_list) }
    end

    # Finds files that were to be tracked but were not loaded, and
    # initializes their line-by-line coverage to zero (or nil for
    # comments / whitespace).
    def add_not_loaded_files(result)
      globs = unloaded_file_discovery_globs
      return [result, Set.new] if globs.empty?

      inject_unloaded_files(result.dup, discover_unloaded_paths(globs))
    end

    # Globs to expand on disk when injecting unloaded files into the
    # result. Combines the legacy `track_files` glob (additive only)
    # with every string glob declared via `cover` (also restrictive,
    # but the restriction lives in `Result#apply_cover_filters!`).
    def unloaded_file_discovery_globs
      [tracked_files, *cover_globs].compact
    end

    # Expand the given globs relative to SimpleCov.root, not Dir.pwd —
    # test runners that chdir (or CI scripts that invoke the suite
    # from a subdir) would otherwise silently miss the unloaded-file
    # injection and produce a different file set per environment. See
    # issue #1106.
    def discover_unloaded_paths(globs)
      globs.flat_map { |glob| Dir.glob(glob, base: root) }.uniq
    end

    def inject_unloaded_files(result, candidate_paths)
      not_loaded_files = candidate_paths.each_with_object(Set.new) do |file, set|
        absolute_path = File.expand_path(file, root)
        next if result.key?(absolute_path)

        result[absolute_path] = SimulateCoverage.call(absolute_path)
        set << absolute_path
      end

      [result, not_loaded_files]
    end

    # Run all the steps that handle processing the raw coverage result.
    # `report:` is true only when this slice is the final result (merging
    # off); with merging on the merged result reports dropped source files,
    # so the per-process slice stays quiet to avoid one warning per worker.
    def process_coverage_result(report:)
      raw = SimpleCov::UselessResultsRemover.call(Coverage.result)
      adapted = SimpleCov::ResultAdapter.call(raw)
      result, not_loaded_files = add_not_loaded_files(adapted)
      @result = SimpleCov::Result.new(result, not_loaded_files: not_loaded_files, report: report)
    end
  end
end
