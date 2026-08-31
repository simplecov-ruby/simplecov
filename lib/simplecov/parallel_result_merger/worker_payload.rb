# frozen_string_literal: true

module SimpleCov
  module ParallelResultMerger
    # What a worker ships back over its pipe: the `[command_names, coverage]` pair
    # its slice folded to, the tracked paths the slice carried, and the slice's
    # context-map union. Building and folding live together so the pipe format
    # has one owner. The parent needs the union across every worker of the
    # tracked paths, to know what nothing loaded, and of the maps, to judge the
    # all-or-nothing rule over the whole run rather than per slice.
    module WorkerPayload
      extend self

      def build(chunk, ignore_timeout:)
        tracked_files = Set.new
        context_maps = ContextMap::Union.new
        pair = ResultMerger.absorb_results(chunk, ignore_timeout: ignore_timeout,
                                           &ResultMerger.entry_collector(tracked_files, context_maps))
        [pair, tracked_files.to_a, context_maps]
      end

      def absorb(payload, tracked_files, context_maps)
        _pair, tracked, maps = payload
        tracked_files.merge(tracked)
        context_maps.absorb_union(maps)
      end

      def pair(payload)
        payload.first
      end
    end
  end
end
