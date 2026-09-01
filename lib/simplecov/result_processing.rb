# frozen_string_literal: true

module SimpleCov
  class << self
    # By default `collate` ignores the merge_timeout so all results in all
    # files specified will be merged. Pass `ignore_timeout: false` to honor it.
    #
    # `processes:` above 1 fans the merge out across that many forked workers.
    # The report is identical either way, not merely equivalent. The count is
    # deliberately not clamped to the machine's core count nor gated on a
    # minimum number of resultsets: what a collate job can afford is the
    # caller's call. Anything below 1 is taken as 1, so an unset
    # `SIMPLECOV_CONCURRENCY` needs no default of its own.
    def collate(result_filenames, profile = nil, processes: ENV["SIMPLECOV_CONCURRENCY"].to_i,
      ignore_timeout: true, &)
      raise ArgumentError, "There are no reports to be merged" if result_filenames.empty?

      initial_setup(profile, &)

      current_run.result = ParallelResultMerger.merge_and_store(*result_filenames, processes: [1, processes].max,
        ignore_timeout: ignore_timeout)

      current_run.collating_result = true
      run_exit_tasks!
    ensure
      current_run.collating_result = false
    end

    def result
      return current_run.result if result?

      merge = merging
      collect_own_coverage(standalone: !merge)
      merge_own_slice if merge
      current_run.result
    end

    def merge_own_slice
      ResultMerger.store_result(result) if result?
      return unless merge_finalization_owner?

      wait_for_other_processes
      current_run.result = ResultMerger.merged_result
    end

    # `standalone` is true when no merge step follows, which makes this the
    # final result: the one that reports dropped source files and injects
    # unloaded files. When a merge does follow, both jobs belong to the merge.
    def collect_own_coverage(standalone:)
      return unless defined?(Coverage) && Coverage.running?

      process_coverage_result(report: standalone, inject_unloaded: standalone)
    end

    def filtered(files)
      result = files.to_a
      filters.each do |filter|
        result = result.reject { |source_file| filter.matches?(source_file) }
      end
      FileList.new result
    end

    # Files matched by no group fall into the implicit "Ungrouped" bucket.
    def grouped(files, groups: default_groups)
      return {} if GroupNames.validate!(groups.keys).empty?

      grouped = groups.transform_values do |filter|
        FileList.new(files.select { |source_file| filter.matches?(source_file) })
      end

      in_group = grouped_file_set(grouped)
      ungrouped = files.reject { |source_file| in_group.include?(source_file) }
      grouped[GroupNames::UNGROUPED] = FileList.new(ungrouped) if ungrouped.any?

      grouped
    end

    def load_profile(name)
      profiles.load(name)
    end

    def clear_result
      current_run.result = nil
    end

    # @api private -- floored (#679) so the next run can compute drift.
    def write_last_run(result)
      LastRun.write(
        result: result.coverage_statistics.transform_values { |stats| round_coverage(stats.percent) }
      )
    end

    # @api private -- floored, to be extra strict.
    def round_coverage(coverage)
      coverage.floor(2)
    end

    # @api private -- the seam `SimpleCov::ResultMerger` injects through. Public
    # only because the merge runs in another object, on behalf of processes
    # whose configuration it may not share, so it supplies the paths itself.
    def inject_unloaded_files(result, candidate_paths, synthesize: nil, lines: nil)
      return [result, Set.new] if candidate_paths.empty?

      # Synthesizing branch and method tuples means parsing every tracked file
      # that wasn't loaded, about half the cost of simulating one, and nothing
      # reads those tuples when neither criterion is enabled. The same goes for
      # line data, which a branch-only or method-only run neither reports nor
      # receives from `Coverage` for the files it loaded (#1250).
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
    # Recorded on the result so a merge in another process can inject the ones
    # nobody loaded without needing this process's `cover` / `track_files`
    # configuration. A standalone `collate` never ran `SimpleCov.start` (#1250).
    def tracked_file_paths
      UnloadedFileInjector.discover(
        unloaded_file_discovery_globs, root: root, reject: filters.select(&:path_only?)
      )
    end

    # The legacy `track_files` glob (additive only) plus every string glob
    # declared via `cover` (also restrictive, but the restriction lives in
    # `Result#apply_cover_filters!`).
    def unloaded_file_discovery_globs
      [tracked_files, *cover_globs].compact
    end

    # `report:` and `inject_unloaded:` are false when a merge step follows.
    # Only the union of every process's loaded files says what was really never
    # loaded, and the merged result is the one that reports dropped source
    # files, so a per-process slice would warn once per worker and simulate
    # nearly the whole project only to have it merged away (#1250).
    def process_coverage_result(report:, inject_unloaded: true)
      # Templates nobody rendered are compiled into the running Coverage so they
      # arrive at 0% below rather than being absent. Needs a live Coverage and
      # ActionView, which rules out the merge point that does the same job for
      # unloaded `.rb` files.
      ViewCoverage.compile_unrendered
      raw = UselessResultsRemover.call(Coverage.result)
      adapted = ResultAdapter.call(raw)
      # `Result#to_hash` serializes coverage after filtering, so a file this
      # process loaded and then filtered out would otherwise be recorded as
      # tracked while absent from the stored coverage, and the merge would
      # simulate it back in as never-loaded (#1250).
      tracked = tracked_file_paths - adapted.keys
      result, not_loaded = inject_unloaded ? inject_unloaded_files(adapted, tracked) : [adapted, Set.new]
      current_run.result = build_result(raw, result, not_loaded: not_loaded, tracked: tracked, report: report)
    end

    def build_result(raw, coverage, not_loaded:, tracked:, report:)
      Result.new(
        coverage, not_loaded_files: not_loaded, tracked_files: tracked, run_id: run_id,
        worker_id: worker_id, contexts: test_tracker&.recorded_map(closing: raw), report: report
      )
    end
  end
end
