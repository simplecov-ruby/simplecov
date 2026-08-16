# frozen_string_literal: true

module SimpleCov
  class Result
    # The Result half of the `.resultset.json` entry format: how a Result
    # serializes itself into an entry (`#to_hash`). The reverse direction,
    # `Result.from_hash`, stays next to `#initialize` in result.rb, and the
    # tolerant parsing of entries other processes wrote lives in
    # `ResultMerger::ResultsetFile`.
    module Serialization
      # Returns a hash representation of this Result that can be used for marshalling it into JSON
      def to_hash
        data = {"coverage" => coverage, "timestamp" => created_at.to_f} #: Hash[String, untyped]
        data["run_id"] = run_id if run_id
        data["worker_id"] = worker_id if worker_id
        # Omitted when empty so a run that tracks nothing writes the shape it
        # always has, and so the key only appears where it carries information.
        data["tracked_files"] = tracked_files unless tracked_files.empty?
        append_contexts(data)
        {command_name => data}
      end

    private

      # Serialized whenever a map was recorded, even an empty one: for the
      # merge, the key's presence is the signal that this result tracked
      # tests, which is what lets it tell "tracked and covered nothing" from
      # "never tracked" (only the latter drops the merged map). The map's
      # files are restricted to this result's post-filter universe, so the
      # map sits beside exactly the coverage it annotates.
      def append_contexts(data)
        map = contexts
        return unless map

        data["contexts"] = map.to_h(only: Set.new(filenames))
      end

      # A live result's criterion keys are Symbols (`:lines`, `:branches`),
      # while entries parsed back from `.resultset.json` carry Strings, and
      # the combiners read only String keys. Serialize with String keys so a
      # live result merged against a stored entry contributes its counts
      # instead of being silently dropped for every shared file.
      def coverage
        original_result.slice(*filenames).transform_values do |file_coverage|
          file_coverage.transform_keys(&:to_s)
        end
      end
    end
  end
end
