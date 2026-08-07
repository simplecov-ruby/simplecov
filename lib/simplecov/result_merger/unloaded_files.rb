# frozen_string_literal: true

module SimpleCov
  module ResultMerger
    # The merge step's half of unloaded-file handling.
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
        SimpleCov.inject_unloaded_files(coverage, tracked_files.to_a)
      end

      # Which files no contributing process ever loaded. Injection reports the
      # ones it added, but a file can also arrive already simulated from a
      # resultset this merge didn't inject into, so the merged line counts are
      # still consulted, using the same signal
      # `Combine::CoverageAccumulator` reconciles synthesized tuples on.
      #
      # A file is judged only when it has line data. A branch-only or
      # method-only run reports none for the files it loaded, which would
      # otherwise read as "never executed" and mark the whole report not loaded.
      # `SimulateCoverage` omits lines under those criteria too, so nothing is
      # judged rather than misjudged.
      def never_executed(coverage)
        coverage.each_with_object(Set.new) do |(filename, file_coverage), set|
          next if Array(file_coverage["lines"]).empty?

          set << filename unless Combine::CoverageAccumulator.executed?(file_coverage["lines"])
        end
      end
    end
  end
end
