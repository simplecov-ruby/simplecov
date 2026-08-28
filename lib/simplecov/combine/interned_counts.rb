# frozen_string_literal: true

module SimpleCov
  module Combine
    # The inner merge loop the branches and methods combiners share:
    # fold `source`'s tuple => count pairs into `target`, an interned
    # table keyed by each tuple's merge identity and holding
    # `[raw_key, count]` pairs. The first-seen raw key is kept for
    # display; counts sum. `target` and its pairs are always built by
    # this loop, so updating them in place can't reach data a caller
    # still holds.
    module InternedCounts
      extend self

      # @return [Hash] `target`
      def absorb_counts(target, source, identities)
        source.each do |key, count|
          interned = identities[key]
          entry = target[interned]
          if entry
            entry[1] += count
          else
            target[interned] = [key, count]
          end
        end
        target
      end
    end
  end
end
