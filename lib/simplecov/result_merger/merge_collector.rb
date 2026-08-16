# frozen_string_literal: true

module SimpleCov
  module ResultMerger
    # Builds the observe block a merge hands to `absorb_results`, fanning
    # each resultset's surviving entries out to the merge's accumulators
    # (tracked files and the per-test contexts union).
    module MergeCollector
    module_function

      def call(tracked_files, contexts)
        tracked = UnloadedFiles.collector(tracked_files)
        lambda do |surviving|
          tracked.call(surviving)
          contexts.observe(surviving)
        end
      end
    end
  end
end
