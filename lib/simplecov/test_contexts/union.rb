# frozen_string_literal: true

require_relative "test_table"
require_relative "map"

module SimpleCov
  module TestContexts
    # Unions the recordings of every resultset entry a merge touches,
    # joined on the rerun-id string. All-or-drop: a partial union under
    # coverage that includes unrecorded runs would misattribute, so the
    # merged recording exists only when every entry carried one.
    class Union
      def initialize
        @table = TestTable.new
        @files = Hash.new { |files, path| files[path] = Hash.new(0) }
        @incomplete = false
        @observed = false
        @warned_about_drop = false
      end

      def observe(resultset_entries)
        resultset_entries.each_value { |data| absorb_entry(data) }
      end

      def absorb_entry(data)
        map = Map.from_hash(data["test_contexts"])
        map ? absorb(map) : mark_incomplete!
      end

      def absorb(map)
        @observed = true
        indices = map.tests.map { |id, name| @table.intern(id, name) }
        map.each_file do |path, masks|
          target = @files[path]
          masks.each { |index, mask| target[indices.fetch(index)] |= mask }
        end
      end

      def mark_incomplete!
        @incomplete = true
      end

      # The merged recording, or nil (some entry lacked one, or nothing
      # was observed).
      def result
        return nil if @incomplete || !@observed

        Map.snapshot(@table, @files)
      end

      def dropped_mixed?
        @incomplete && @observed
      end

      # Separate from `result` so workers serializing through `dump`
      # don't each warn; the process assembling the final result calls this.
      def result_with_drop_warning
        warn_about_dropped_recording if dropped_mixed?
        result
      end

      # The parallel-merge pipe payload; an empty slice is vacuously complete.
      def dump
        [@incomplete, result&.to_h]
      end

      def absorb_dump(pair)
        incomplete, payload = pair
        return mark_incomplete! if incomplete
        return unless payload

        map = Map.from_hash(payload)
        map ? absorb(map) : mark_incomplete!
      end

      # `ResultMerger.merged_entry`'s rule for two concurrent entries
      # sharing a command name.
      def self.carry(entry, existing, incoming)
        union = new
        union.absorb_entry(existing)
        union.absorb_entry(incoming)
        merged = union.result_with_drop_warning
        return entry.merge("test_contexts" => merged.to_h) if merged

        entry.except("test_contexts")
      end

    private

      # The respond_to? guard keeps this class loadable without the
      # SimpleCov singleton (the CLI reaches here without booting it).
      def warn_about_dropped_recording
        return if @warned_about_drop

        @warned_about_drop = true
        # simplecov:disable branch — only the CLI reaches this class without
        # the singleton's configuration; this suite always runs with it
        return if SimpleCov.respond_to?(:print_errors) && !SimpleCov.print_errors
        # simplecov:enable

        warn "[SimpleCov]: some merged results carry per-test contexts and some do not (a run without " \
             "`test_contexts :per_test`, or a forked test process); keeping only part of the recording " \
             "would misattribute lines, so the merged result drops it."
      end
    end
  end
end
