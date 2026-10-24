# frozen_string_literal: true

module SimpleCov
  module ResultMerger
    module Contexts
      extend self

      # The same union-or-drop rule the cross-suite merge applies: the union when
      # both sides recorded a map, no map at all when either did not, since a
      # partial map would present one runner's tests as the pair's. `entry` starts
      # as a copy of `incoming`, so the drop has to remove the key rather than
      # merely decline to add it.
      def carry(entry, existing, incoming)
        ours = ContextMap.from_hash(existing["contexts"])
        theirs = ContextMap.from_hash(incoming["contexts"])
        return dropped(entry, existing) unless ours && theirs

        entry.merge("contexts" => superseded(ours, theirs).to_h)
      end

      # A later run under the same command name keeps what the earlier run
      # recorded for the tests it did not run itself. Otherwise rerunning one
      # test file leaves a map that knows only that file, and `affected` then
      # selects nothing for a change only the other tests cover.
      def carry_forward(incoming, existing)
        return incoming unless incoming && existing

        theirs = ContextMap.from_hash(incoming["contexts"])
        ours = ContextMap.from_hash(existing["contexts"])
        recorded_at = existing["timestamp"]
        return incoming unless theirs && ours && recorded_at.is_a?(Numeric)

        incoming.merge("contexts" => superseded(still_valid(ours, recorded_at), theirs).to_h)
      end

      private

      # Without the map, but with the reason either side gave for dropping its
      # own, the incoming side's first.
      def dropped(entry, existing)
        reason = existing["contexts_dropped"]
        without = entry.except("contexts")
        reason ? {"contexts_dropped" => reason}.merge(without) : without
      end

      # A test recorded again replaces its earlier lines rather than adding to
      # them. Replaced by test, not by file, since rerunning one example or only
      # the failures leaves the file's other tests as they were.
      def superseded(ours, theirs)
        ours.without { |context_id| theirs.include?(context_id) }.absorb(theirs)
      end

      # A test whose file is gone can never run again. A source file changed
      # since the earlier run has moved lines under its recorded bitmaps, so its
      # tests are credited with every line instead: selecting them too often is
      # safe, missing them is not.
      def still_valid(map, recorded_at)
        kept = map.without { |context_id| deleted_test?(context_id) }
        kept.paths.each do |path|
          lines = changed_lines(path, recorded_at)
          kept.widen(path, lines) if lines
        end
        kept
      end

      def deleted_test?(context_id)
        file = context_id.sub(TEST_ID_TAIL, "")
        located = file.include?("/") || file.end_with?(".rb")
        located && !File.exist?(File.expand_path(file, SimpleCov.root))
      end

      def changed_lines(path, recorded_at)
        return unless File.mtime(path).to_f > recorded_at

        (1 << File.foreach(path).count) - 1
      rescue SystemCallError
        nil
      end
    end
  end
end
