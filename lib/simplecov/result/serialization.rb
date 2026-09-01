# frozen_string_literal: true

module SimpleCov
  class Result
    module Serialization
      def to_hash
        data = {"coverage" => coverage, "timestamp" => created_at.to_f} #: Hash[String, untyped]
        data["run_id"] = run_id if run_id
        data["worker_id"] = worker_id if worker_id
        data["tracked_files"] = tracked_files unless tracked_files.empty?
        append_contexts(data)
        {command_name => data}
      end

      private

      # Serialized whenever a map was recorded, even an empty one: for the merge,
      # the key's presence is the signal that this result tracked tests, which is
      # what lets it tell "tracked and covered nothing" from "never tracked". The
      # map's files are restricted to this result's post-filter universe.
      def append_contexts(data)
        map = contexts
        return unless map

        data["contexts"] = map.to_h(only: context_filenames)
      end

      def context_filenames
        Set.new(filenames)
      end

      # A live result's criterion keys are Symbols while entries parsed back from
      # `.resultset.json` carry Strings, and the combiners read only String keys.
      # Serializing with String keys is what lets a live result merged against a
      # stored entry contribute its counts instead of being dropped.
      def coverage
        original_result.slice(*filenames).transform_values do |file_coverage|
          file_coverage.transform_keys(&:to_s)
        end
      end
    end
  end
end
