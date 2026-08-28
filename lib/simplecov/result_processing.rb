# frozen_string_literal: true

# Result-building façade: turns the raw `Coverage.result` hash into a
# `SimpleCov::Result`, applies filters and groups, drives merging
# across test suites via `SimpleCov::ResultMerger`, and exposes the
# `collate` entry point for stitching disparate resultsets together.
#
# rubocop:disable Metrics/ModuleLength -- one façade over one pipeline, and
# every step of it reads better next to the ones on either side.
module SimpleCov
  class << self
    #
    # Collate a series of SimpleCov result files into a single SimpleCov output.
    #
    # See README for usage. By default `collate` ignores the merge_timeout
    # so all results in all files specified will be merged. Pass
    # `ignore_timeout: false` to honor it.
    #
    # `processes:` above 1 fans the merge out across that many forked worker
    # processes, for a collate big enough that reading and parsing the
    # resultsets dominates it. The report is identical either way, not merely
    # equivalent — the workers visit the resultsets in the order the
    # single-process merge visits them — and one process never forks at all.
    # The count is deliberately not clamped to the machine's core count nor
    # gated on some minimum number of resultsets: how many processes a collate
    # job can afford is the caller's call, not SimpleCov's. Anything below 1 is
    # taken as 1, so a count computed from arithmetic that can reach zero needs
    # no guarding. Defaults to `SIMPLECOV_CONCURRENCY`, or 1 when that is
    # unset. See `SimpleCov::ParallelResultMerger`.
    #
    # The concurrency needs no default of its own: an unset variable
    # reads as nothing, and the floor below turns that into one process.
    def collate(result_filenames, profile = nil, processes: ENV["SIMPLECOV_CONCURRENCY"].to_i,
                ignore_timeout: true, &)
      raise ArgumentError, "There are no reports to be merged" if result_filenames.empty?

      initial_setup(profile, &)

      # Use the ResultMerger to produce a single, merged result, ready to use.
      @result = ParallelResultMerger.merge_and_store(*result_filenames, processes: [1, processes].max,
                                                                        ignore_timeout: ignore_timeout)

      @collating_result = true
      run_exit_tasks!
    ensure
      @collating_result = false
    end

    #
    # Returns the result for the current coverage run. With merging enabled,
    # every process stores its own slice, but only the finalization owner reads
    # and caches the merged result.
    #
    def result
      return @result if result?

      use_merging = merging

      collect_own_coverage(standalone: !use_merging)

      # If we're using merging of results, store the current result
      # first (if there is one), then merge the results and return those
      if use_merging
        ResultMerger.store_result(@result) if result?
        return @result unless merge_finalization_owner?

        wait_for_other_processes
        @result = ResultMerger.merged_result
      end

      @result
    end

    # Build this process's slice of the coverage result. `standalone` is true
    # when no merge step follows, which makes this the final result: it is the
    # one that reports dropped source files, and the one that injects unloaded
    # files. When a merge does follow, both jobs belong to the merged result.
    def collect_own_coverage(standalone:)
      return unless defined?(Coverage) && Coverage.running?

      process_coverage_result(report: standalone, inject_unloaded: standalone)
    end

    # Returns nil if the result has not been computed, otherwise the result.
    # The cast restores what `defined?` used to narrow for steep: asking
    # the object whether it holds the variable tells the checker nothing
    # about what is in it.
    def result?
      instance_variable_defined?(:@result) && (_ = @result)
    end

    # @api private — true while `SimpleCov.collate` is running its finalizer.
    def collating_result?
      instance_variable_defined?(:@collating_result) && @collating_result
    end

    # Applies the configured filters to the given array of SimpleCov::SourceFile items
    def filtered(files)
      result = files.to_a
      filters.each do |filter|
        result = result.reject { |source_file| filter.matches?(source_file) }
      end
      FileList.new result
    end

    # Bin the given source files by group filter. `groups:` defaults to
    # `SimpleCov.groups`; pass a Hash explicitly to bin against a
    # different group config (e.g., the snapshot a Result captured at
    # construction). Files matched by no group fall into the implicit
    # "Ungrouped" bucket.
    def grouped(files, groups: default_groups)
      return {} if GroupNames.validate!(groups.keys).empty?

      grouped = groups.transform_values do |filter|
        FileList.new(files.select { |source_file| filter.matches?(source_file) })
      end

      in_group  = grouped_file_set(grouped)
      ungrouped = files.reject { |source_file| in_group.include?(source_file) }
      grouped[GroupNames::UNGROUPED] = FileList.new(ungrouped) if ungrouped.any?

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
      LastRun.write(
        result: result.coverage_statistics.transform_values { |stats| round_coverage(stats.percent) }
      )
    end

    # @api private — round down to two decimals to be extra strict.
    def round_coverage(coverage)
      coverage.floor(2)
    end

    # Add simulated coverage for each of `candidate_paths` the result doesn't
    # already carry, and return it with the set of paths added.
    #
    # @api private — the seam `SimpleCov::ResultMerger` injects through. Public
    # only because the merge runs in another object, on behalf of processes
    # whose configuration it may not share, so it supplies the paths itself.
    def inject_unloaded_files(result, candidate_paths, synthesize: nil, lines: nil)
      return [result, Set.new] if candidate_paths.empty?

      # Synthesizing branch and method tuples means parsing every tracked file
      # that wasn't loaded, which is about half the cost of simulating one.
      # Nothing reads those tuples when neither criterion is enabled —
      # `Combine::CoverageAccumulator` only combines them per criterion, and the
      # statistics drop them the same way — so skip the parse. The same goes
      # for line data, which a branch-only or method-only run neither reports
      # nor receives from `Coverage` for the files it loaded. See #1250.
      UnloadedFileInjector.call(
        result, candidate_paths,
        synthesize: synthesize.nil? ? branch_coverage? || method_coverage? : synthesize,
        lines: lines.nil? ? line_coverage? : lines
      )
    end

  private

    def initial_setup(profile, &block)
      load_profile(profile) if profile
      configure(&block) if block
    end

    def grouped_file_set(grouped)
      grouped.values.each_with_object(Set.new) { |file_list, set| set.merge(file_list) }
    end

    # Every path this process was told to track, whether or not it loaded them.
    # Recorded on the result (and from there into the resultset) so that a merge
    # in another process can inject the ones nobody loaded without needing this
    # process's `cover` / `track_files` configuration. A standalone `collate`
    # never ran `SimpleCov.start` and so has none of its own. See #1250.
    def tracked_file_paths
      UnloadedFileInjector.discover(
        unloaded_file_discovery_globs, root: root, reject: filters.select(&:path_only?)
      )
    end

    # Globs to expand on disk when injecting unloaded files into the
    # result. Combines the legacy `track_files` glob (additive only)
    # with every string glob declared via `cover` (also restrictive,
    # but the restriction lives in `Result#apply_cover_filters!`).
    def unloaded_file_discovery_globs
      [tracked_files, *cover_globs].compact
    end

    # Run all the steps that handle processing the raw coverage result.
    # `report:` is true only when this slice is the final result (merging
    # off); with merging on the merged result reports dropped source files,
    # so the per-process slice stays quiet to avoid one warning per worker.
    #
    # `inject_unloaded:` is likewise false when a merge step follows. Only the
    # union of every process's loaded files says what was really never loaded,
    # so injecting here means each worker simulates nearly the whole project
    # and all but one of those passes is merged away. See #1250.
    def process_coverage_result(report:, inject_unloaded: true)
      # Templates nobody rendered are compiled into the running Coverage so
      # they arrive at 0% below rather than being absent. Needs a live Coverage
      # and ActionView, which rules out the merge point that does the same job
      # for unloaded `.rb` files.
      ViewCoverage.compile_unrendered
      raw = UselessResultsRemover.call(Coverage.result)
      adapted = ResultAdapter.call(raw)
      # What this process was told to track and did not load. Subtracting what
      # it loaded matters because `Result#to_hash` serializes coverage after
      # filtering: a file this process loaded and then filtered out would
      # otherwise be recorded as tracked while absent from the stored coverage,
      # and the merge would simulate it back in as never-loaded. See #1250.
      tracked = tracked_file_paths - adapted.keys
      result, not_loaded = inject_unloaded ? inject_unloaded_files(adapted, tracked) : [adapted, Set.new]
      @result = Result.new(
        result, not_loaded_files: not_loaded, tracked_files: tracked, run_id: run_id,
                worker_id: worker_id, contexts: test_tracker&.recorded_map(closing: raw), report: report
      )
    end
  end
end
# rubocop:enable Metrics/ModuleLength
