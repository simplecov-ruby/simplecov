# frozen_string_literal: true

require_relative "result_merger/legacy_format_adapter"
require_relative "result_merger/resultset_file"
require_relative "result_merger/resultset_run_identity"
require_relative "result_merger/resultset_store"
require_relative "result_merger/contexts"
require_relative "result_merger/unloaded_files"

module SimpleCov
  #
  # Singleton that is responsible for caching, loading and merging
  # SimpleCov::Results into a single result for coverage analysis based
  # upon multiple test suites.
  #
  module ResultMerger
    extend ResultsetRunIdentity

    class << self
      def resultset_path
        ResultsetStore.resultset_path
      end

      def merge_and_store(*file_paths, ignore_timeout: false)
        result = merge_results(*file_paths, ignore_timeout: ignore_timeout)
        store_result(result) if result
        result
      end

      def merge_results(*file_paths, ignore_timeout: false)
        # Tracked paths and test maps are collected as each resultset is
        # parsed, so files are still read and discarded one at a time.
        # See #1250.
        tracked_files = Set.new
        context_maps = ContextMap::Union.new
        command_names, coverage = absorb_results(file_paths, ignore_timeout: ignore_timeout,
                                                 &entry_collector(tracked_files, context_maps))
        create_result(command_names, coverage, tracked_files: tracked_files, contexts: context_maps.map)
      end

      # One block over the entries each resultset contributes to the merge,
      # feeding every merge-side accumulator in a single pass: the tracked
      # paths (see #1250) and the per-test map union.
      def entry_collector(tracked_files, context_maps)
        collectors = [UnloadedFiles.collector(tracked_files), context_maps.collector]
        ->(surviving) { collectors.each { |collector| collector.call(surviving) } }
      end

      #
      # Reads every resultset and folds it into one merged coverage, stopping
      # short of building a `SimpleCov::Result`.
      #
      # It is intentional here that files are only read in and parsed one at a time.
      #
      # In big CI setups you might deal with 100s of CI jobs and each one producing Megabytes
      # of data. Reading them all in easily produces Gigabytes of memory consumption which
      # we want to avoid.
      #
      # For similar reasons a SimpleCov::Result is only created in the end as that'd create
      # even more data especially when it also reads in all source files.
      #
      # One accumulator absorbs the whole run, rather than folding each file
      # into the merged-so-far pairwise: the pairwise form rebuilt every
      # file's coverage once per resultset, which is what made merging a
      # large parallel run's results the dominant cost of `collate`.
      # Absorbing is still one resultset at a time, so the memory ceiling
      # above is unchanged.
      #
      # `file_paths` is only ever iterated, so a caller that wants to observe
      # the merge as it goes can hand in any Enumerable — `benchmarks/collate`
      # passes an Enumerator that reports progress — rather than reimplement
      # this loop and risk timing something other than what ships.
      #
      # @return [Array] the command names and the merged coverage
      #
      def absorb_results(file_paths, ignore_timeout: false, &on_parse)
        Combine::CoverageAccumulator.fold(
          file_paths.lazy.map { |file_path| valid_results(file_path, ignore_timeout: ignore_timeout, &on_parse) }
        )
      end

      # Yields the surviving entries before they are reduced.
      def valid_results(file_path, ignore_timeout: false, &on_parse)
        merge_valid_results(ResultsetFile.parse(file_path), ignore_timeout: ignore_timeout, &on_parse)
      end

      # Yields the entries that survived the merge timeout, so a caller that
      # wants to observe what a resultset carried sees only what is being
      # merged. An expired entry contributes nothing, tracked paths included.
      def merge_valid_results(results, ignore_timeout: false)
        results = drop_expired_results(results) unless ignore_timeout
        yield results if block_given?

        command_plus_coverage = results.map do |command_name, data|
          [[command_name], LegacyFormatAdapter.call(data.fetch("coverage"))]
        end

        # one file itself _might_ include multiple test runs
        merge_coverage(*command_plus_coverage)
      end

      def drop_expired_results(results)
        fresh, expired = results.partition { |_command_name, data| within_merge_timeout?(data) }
        return results if expired.empty?

        warn_about_expired_results(expired.map(&:first))
        fresh.to_h
      end

      def within_merge_timeout?(data)
        (Time.now - Time.at(data.fetch("timestamp"))) < SimpleCov.merge_timeout
      end

      def warn_about_expired_results(expired_command_names)
        # Respect quiet configurations and keep this consistent with every
        # other SimpleCov diagnostic. Ordinary parallel workers only store
        # their own slice; the selected final process performs this merge.
        return unless SimpleCov.print_errors

        warn "[SimpleCov]: Excluded #{expired_command_names.size} result(s) older than " \
             "merge_timeout (#{SimpleCov.merge_timeout}s) from the merged report: " \
             "#{expired_command_names.sort.join(', ')}. " \
             "Increase SimpleCov.merge_timeout to include them."
      end

      def create_result(command_names, coverage, tracked_files: Set.new, contexts: nil)
        return nil unless coverage

        command_name = command_names.reject(&:empty?).sort.join(", ")
        coverage, injected = UnloadedFiles.inject(coverage, tracked_files)
        # The merged result is the authoritative one users actually see, so
        # it's the one that warns about source files dropped because they no
        # longer exist on disk (issue #980). The per-process slices built in
        # `process_coverage_result` stay quiet to avoid one warning per worker.
        SimpleCov::Result.new(
          coverage,
          command_name: command_name, contexts: contexts, report: true,
          not_loaded_files: UnloadedFiles.never_executed(coverage) | injected,
          tracked_files: tracked_files.to_a
        )
      end

      def merge_coverage(*results)
        return [[""], nil] if results.empty?
        return results.first if results.size == 1

        Combine::CoverageAccumulator.fold(results)
      end

      #
      # Gets all SimpleCov::Results stored in resultset, merges them and produces a new
      # SimpleCov::Result with merged coverage data and the command_name
      # for the result consisting of a join on all source result's names
      def merged_result
        tracked_files = Set.new
        context_maps = ContextMap::Union.new
        command_names, coverage = merge_valid_results(read_resultset, &entry_collector(tracked_files, context_maps))
        create_result(command_names, coverage, tracked_files: tracked_files, contexts: context_maps.map)
      end

      def read_resultset
        content = synchronize_resultset { ResultsetFile.read(resultset_path) }
        ResultsetFile.decode(content)
      end

      # Saves the given SimpleCov::Result in the resultset cache
      def store_result(result) # rubocop:disable Naming/PredicateMethod
        synchronize_resultset do
          # Ensure we have the latest, in case it was already cached
          new_resultset = read_resultset

          # A single result only ever has one command_name, see `SimpleCov::Result#to_hash`
          command_name, data = result.to_hash.first
          new_resultset[command_name] = merged_entry(new_resultset[command_name], data)

          ResultsetStore.write(new_resultset)
        end
        true
      end

      # If an entry with the same command_name was written AFTER our process
      # started, a sibling test runner (typically a subprocess our parent
      # process shelled out to) wrote it. Combine coverage data rather than
      # overwriting, so an empty parent-process result doesn't clobber the
      # subprocess's real data. See https://github.com/simplecov-ruby/simplecov/issues/581.
      def merged_entry(existing, incoming)
        return incoming unless concurrent_runner_entry?(existing, incoming)

        merged = incoming.merge(
          "coverage" => Combine::ResultsCombiner.combine(existing["coverage"], incoming["coverage"])
        )
        merged = Contexts.carry(merged, existing, incoming)
        UnloadedFiles.carry_tracked(merged, existing, incoming)
      end

      def synchronize_resultset(&)
        ResultsetStore.synchronize(&)
      end
    end
  end
end
