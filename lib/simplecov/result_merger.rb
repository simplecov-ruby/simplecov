# frozen_string_literal: true

require_relative "result_merger/legacy_format_adapter"
require_relative "result_merger/resultset_file"
require_relative "result_merger/resultset_store"

module SimpleCov
  #
  # Singleton that is responsible for caching, loading and merging
  # SimpleCov::Results into a single result for coverage analysis based
  # upon multiple test suites.
  #
  module ResultMerger
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
        command_names, coverage = absorb_results(file_paths, ignore_timeout: ignore_timeout)
        create_result(command_names, coverage)
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
      def absorb_results(file_paths, ignore_timeout: false)
        Combine::CoverageAccumulator.fold(
          file_paths.lazy.map { |file_path| valid_results(file_path, ignore_timeout: ignore_timeout) }
        )
      end

      def valid_results(file_path, ignore_timeout: false)
        merge_valid_results(ResultsetFile.parse(file_path), ignore_timeout: ignore_timeout)
      end

      def merge_valid_results(results, ignore_timeout: false)
        results = drop_expired_results(results) unless ignore_timeout

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
        # Subprocesses merge the resultset too (each forked worker calls
        # `SimpleCov.result` to store its slice), and the default `at_fork`
        # sets `print_errors false` for them. Without this guard the warning
        # is emitted once per worker — N copies of the same message for an
        # N-worker run. Gate on `print_errors` like every other SimpleCov
        # warning so only the reporting process speaks up.
        return unless SimpleCov.print_errors

        warn "[SimpleCov]: Excluded #{expired_command_names.size} result(s) older than " \
             "merge_timeout (#{SimpleCov.merge_timeout}s) from the merged report: " \
             "#{expired_command_names.sort.join(', ')}. " \
             "Increase SimpleCov.merge_timeout to include them."
      end

      def create_result(command_names, coverage)
        return nil unless coverage

        command_name = command_names.reject(&:empty?).sort.join(", ")
        # The merged result is the authoritative one users actually see, so
        # it's the one that warns about source files dropped because they no
        # longer exist on disk (issue #980). The per-process slices built in
        # `process_coverage_result` stay quiet to avoid one warning per worker.
        SimpleCov::Result.new(
          coverage,
          command_name: command_name,
          not_loaded_files: never_executed_files(coverage),
          report: true
        )
      end

      # Which files no contributing process ever loaded. The loaded/not-loaded
      # distinction isn't serialized — `Result#to_hash` writes only coverage and
      # a timestamp — so it has to be re-derived here from the merged line
      # counts, using the same signal `Combine::CoverageAccumulator` reconciles
      # synthesized tuples on.
      # Without it every file in a merged report is `loaded: true`, and the #902
      # rule that reports 0% rather than a misleading 100% for a never-loaded
      # file with no branch or method data can never fire on a merged result.
      # See #1250.
      #
      # Line counts are the only signal available, so a file is judged only when
      # it has some. A branch-only or method-only run reports no line data for
      # the files it loaded, which would otherwise read as "never executed" and
      # mark every file in the report not loaded; `SimulateCoverage` omits lines
      # under those criteria too, so nothing is judged rather than misjudged.
      def never_executed_files(coverage)
        coverage.each_with_object(Set.new) do |(filename, file_coverage), set|
          next if Array(file_coverage["lines"]).empty?

          set << filename unless Combine::CoverageAccumulator.executed?(file_coverage["lines"])
        end
      end

      # timestamps are dropped here, which is intentional (we merge them, the
      # merged result gets a new time stamp as of now)
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
        command_names, coverage = merge_valid_results(read_resultset)
        create_result(command_names, coverage)
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
        return incoming unless concurrent_runner_entry?(existing)

        incoming.merge(
          "coverage" => Combine::ResultsCombiner.combine(existing["coverage"], incoming["coverage"])
        )
      end

      def concurrent_runner_entry?(entry)
        return false unless entry.is_a?(Hash)

        timestamp = entry["timestamp"]
        process_start = SimpleCov.process_start_time
        timestamp && process_start && timestamp.to_i >= process_start.to_i
      end

      def synchronize_resultset(&)
        ResultsetStore.synchronize(&)
      end
    end
  end
end
