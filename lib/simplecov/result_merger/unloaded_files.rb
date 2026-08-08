# frozen_string_literal: true

module SimpleCov
  module ResultMerger
    # The merge step's half of unloaded-file handling: the policy of when
    # to inject and which criteria simulated files carry. The mechanism —
    # expanding globs and simulating each file — is
    # `SimpleCov::UnloadedFileInjector`, an easy name to confuse with this
    # one.
    #
    # Injection moved here from the individual processes because only the union
    # of what they all loaded says what was really never loaded. Doing it per
    # process meant N workers simulated the same file up to N times and the
    # merge threw all but one away. See #1250.
    module UnloadedFiles
    module_function

      # The union of what every contributing process was told to track. Absent
      # from resultsets written before this was recorded, in which case those
      # processes injected their own unloaded files and the data is already in
      # the coverage hash.
      # A collector for the merge to hand `merge_valid_results`, gathering the
      # tracked paths of every resultset that survives the merge timeout.
      def collector(into)
        ->(surviving) { into.merge(tracked_in(surviving)) }
      end

      def tracked_in(resultset)
        resultset.each_with_object(Set.new) do |(_command_name, data), set|
          set.merge(Array(data["tracked_files"]))
        end
      end

      # Concurrent workers sharing a command name may have been told to track
      # different sets, so keep both rather than letting the later write win.
      def carry_tracked(entry, existing, incoming)
        tracked = Array(existing["tracked_files"]) | Array(incoming["tracked_files"])
        tracked.empty? ? entry : entry.merge("tracked_files" => tracked)
      end

      # Simulate each tracked file the merged coverage doesn't already carry.
      # The paths come from the resultsets rather than this process's own
      # configuration, which a standalone `collate` would not have: it never ran
      # `SimpleCov.start`, so it has no `cover` glob to expand. Idempotent, so
      # resultsets from an older SimpleCov (or from a `merging false` process)
      # that already carry their unloaded files pass through untouched.
      def inject(coverage, tracked_files)
        SimpleCov.inject_unloaded_files(
          coverage, tracked_files.to_a,
          synthesize: carries?(coverage, "branches") || carries?(coverage, "methods"),
          lines: carries?(coverage, "lines")
        )
      end

      # A simulated file should have the same shape as the files it is being
      # merged alongside, so the criteria come from the merged data rather than
      # from this process's configuration, which is not necessarily the
      # configuration any contributing process measured under: `simplecov merge`
      # never ran `SimpleCov.start` at all. Giving injected files fewer tables
      # than their neighbours is what inflates the percentage #1059 fixed.
      #
      # Falls back to the configuration when there is nothing to be consistent
      # with, which is a merge of resultsets that carried no files.
      def carries?(coverage, criterion)
        return SimpleCov.public_send(CRITERION_PREDICATES.fetch(criterion)) if coverage.empty?

        coverage.any? { |_filename, file_coverage| file_coverage[criterion] }
      end

      CRITERION_PREDICATES = {
        "lines" => :line_coverage?,
        "branches" => :branch_coverage?,
        "methods" => :method_coverage?
      }.freeze
      private_constant :CRITERION_PREDICATES

      # Which files no contributing process ever loaded. Injection reports the
      # ones it added, but a file can also arrive already simulated from a
      # resultset this merge didn't inject into, so the merged line counts are
      # still consulted, using the same signal
      # `Combine::CoverageAccumulator` reconciles synthesized tuples on.
      #
      # A file is judged only when it has a relevant line. A branch-only or
      # method-only run reports no line data at all for the files it loaded,
      # and a loaded file with no executable lines (a comment-only constants
      # stub, say) reports every line as `nil` — either would otherwise read
      # as "never executed" and mark a genuinely loaded file not loaded,
      # turning its branch and method coverage into #902's 0%.
      # `SimulateCoverage` omits lines under those criteria too and gives a
      # simulated file a `0` on every relevant line, so genuinely unloaded
      # files still carry judgeable data, and a simulated file with none is
      # already flagged by injection reporting it.
      def never_executed(coverage)
        coverage.each_with_object(Set.new) do |(filename, file_coverage), set|
          counts = Array(file_coverage["lines"]) #: Array[Integer?]
          next unless counts.any? { |count| !count.nil? }

          set << filename unless Combine::CoverageAccumulator.executed?(file_coverage["lines"])
        end
      end
    end
  end
end
