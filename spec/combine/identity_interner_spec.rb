# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::Combine::IdentityInterner do
  # The interned id is only ever a hash key, so its value carries no
  # meaning beyond "two keys that share an identity share an id". What is
  # pinned here is that much, plus the caching a fold depends on: an
  # identity is derived once per raw key, however often the fold asks.
  describe ".build" do
    # Keys stand in for branch / method tuples: the second element is the
    # part that varies between processes and is ignored, like a branch id.
    def interner
      described_class.build { |key| key.fetch(0) }
    end

    it "numbers identities from zero, in the order they are first seen" do
      ids = interner

      expect([ids[[:a, 1]], ids[[:b, 1]], ids[[:c, 1]]]).to eq([0, 1, 2])
    end

    it "gives two keys with the same identity the same id" do
      ids = interner

      expect(ids[[:a, 1]]).to eq(ids[[:a, 2]])
    end

    it "gives a key whose identity is seen again the earlier id" do
      ids = interner
      first = ids[[:a, 1]]
      ids[[:b, 1]]

      expect(ids[[:a, 2]]).to eq(first)
    end

    it "derives each raw key's identity exactly once" do
      derived = []
      ids = described_class.build do |key|
        derived << key
        key
      end

      3.times { ids[:tuple] }
      ids[:other]

      expect(derived).to eq(%i[tuple other])
    end
  end
end
