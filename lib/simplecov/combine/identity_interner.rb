# frozen_string_literal: true

module SimpleCov
  module Combine
    # Builds the raw-key => interned-identity caches the tuple combiners keep. A
    # key is mapped on first sight and kept: the pairwise fold would otherwise
    # re-derive the accumulator's identities on every one of its merges, always
    # to the same answer.
    #
    # Identities exist only to be hash keys, and `Array#hash` is not memoized, so
    # keying on the identity tuple itself would rehash its elements for every key
    # of both sides of every merge. An Integer hashes as an immediate. Two keys
    # share an id exactly when their identities are equal, so the string and
    # array forms of one key still merge together.
    module IdentityInterner
      extend self

      def build
        ids = {} #: Hash[::Array[untyped], Integer]
        Hash.new do |cache, key|
          identity = yield(key)
          cache[key] = ids[identity] ||= ids.size
        end
      end
    end
  end
end
