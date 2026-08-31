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
        return entry.except("contexts") unless ours && theirs

        entry.merge("contexts" => ours.absorb(theirs).to_h)
      end
    end
  end
end
