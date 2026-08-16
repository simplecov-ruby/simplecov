# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ContextMap do
  subject(:map) { described_class.new }

  let(:lib_file) { File.join(SimpleCov.root, "lib/thing.rb") }
  let(:other_file) { File.join(SimpleCov.root, "lib/other.rb") }

  describe "#record and #covering" do
    it "attributes each recorded line bitmap to its test" do
      map.record("spec/thing_spec.rb:5", lib_file => 0b101)
      map.record("spec/other_spec.rb:9", lib_file => 0b100, other_file => 0b1)

      expect(map.covering(lib_file, 1)).to eq(["spec/thing_spec.rb:5"])
      expect(map.covering(lib_file, 3)).to eq(["spec/other_spec.rb:9", "spec/thing_spec.rb:5"])
      expect(map.covering(other_file, 1)).to eq(["spec/other_spec.rb:9"])
    end

    it "resolves project-relative paths against SimpleCov.root" do
      map.record("spec/thing_spec.rb:5", lib_file => 0b1)

      expect(map.covering("lib/thing.rb", 1)).to eq(["spec/thing_spec.rb:5"])
    end

    it "answers an empty list for an untouched line, an unknown file, and a nonsense line number" do
      map.record("spec/thing_spec.rb:5", lib_file => 0b1)

      expect(map.covering(lib_file, 2)).to eq([])
      expect(map.covering(other_file, 1)).to eq([])
      expect(map.covering(lib_file, 0)).to eq([])
    end

    it "unions the bitmaps of a test recorded more than once" do
      map.record("spec/thing_spec.rb:5", lib_file => 0b1)
      map.record("spec/thing_spec.rb:5", lib_file => 0b10)

      expect(map.covering(lib_file, 1)).to eq(["spec/thing_spec.rb:5"])
      expect(map.covering(lib_file, 2)).to eq(["spec/thing_spec.rb:5"])
      expect(map.contexts).to eq(["spec/thing_spec.rb:5"])
    end

    it "keeps a test that covered nothing, without inventing file entries" do
      map.record("spec/quiet_spec.rb:1", {})
      map.record("spec/zero_spec.rb:2", lib_file => 0)

      expect(map.contexts).to eq(["spec/quiet_spec.rb:1", "spec/zero_spec.rb:2"])
      expect(map.to_h["files"]).to eq({})
    end
  end

  describe "#empty?" do
    it "is empty until a test is recorded" do
      expect(map).to be_empty

      map.record("spec/thing_spec.rb:5", {})
      expect(map).not_to be_empty
    end
  end

  describe "#absorb" do
    it "merges by test id, re-interning the other map's indices" do
      map.record("spec/a_spec.rb:1", lib_file => 0b1)
      other = described_class.new
      # Recorded in a different order, so the raw indices disagree on
      # purpose: index 0 means a different test on each side.
      other.record("spec/b_spec.rb:2", lib_file => 0b10)
      other.record("spec/a_spec.rb:1", lib_file => 0b100)

      map.absorb(other)

      expect(map.covering(lib_file, 1)).to eq(["spec/a_spec.rb:1"])
      expect(map.covering(lib_file, 2)).to eq(["spec/b_spec.rb:2"])
      expect(map.covering(lib_file, 3)).to eq(["spec/a_spec.rb:1"])
      expect(map.contexts).to eq(["spec/a_spec.rb:1", "spec/b_spec.rb:2"])
    end
  end

  describe "#to_h and .from_hash" do
    it "round-trips through the serialized form" do
      map.record("spec/a_spec.rb:1", lib_file => 0b101)
      map.record("spec/b_spec.rb:2", other_file => 0b1)

      restored = described_class.from_hash(map.to_h)

      expect(restored.to_h).to eq(map.to_h)
      expect(restored.covering(lib_file, 3)).to eq(["spec/a_spec.rb:1"])
    end

    it "serializes bitmaps as hex keyed by interned test index, under a format version" do
      map.record("spec/a_spec.rb:1", lib_file => 0b1)
      map.record("spec/b_spec.rb:2", lib_file => 0xff)

      expect(map.to_h).to eq(
        "version" => 1,
        "contexts" => ["spec/a_spec.rb:1", "spec/b_spec.rb:2"],
        "files" => {lib_file => {"0" => "1", "1" => "ff"}}
      )
    end

    # A future format change bumps the version, and an older reader must
    # treat data it cannot interpret as absent rather than misread it.
    it "treats an unknown format version as no map at all" do
      map.record("spec/a_spec.rb:1", lib_file => 0b1)
      dumped = map.to_h

      expect(described_class.from_hash(dumped.merge("version" => 2))).to be_nil
      expect(described_class.from_hash(dumped.except("version"))).to be_nil
    end

    # Recording order varies run to run, so serialization sorts each
    # file's table by test index to keep stored resultsets diffable.
    it "serializes each file's bitmaps in test-index order" do
      map.record("spec/b_spec.rb:2", {})
      map.record("spec/a_spec.rb:1", {})
      other_map = described_class.new
      other_map.record("spec/a_spec.rb:1", lib_file => 0b1)
      other_map.record("spec/b_spec.rb:2", lib_file => 0b10)
      map.absorb(other_map)

      expect(map.to_h["files"][lib_file].keys).to eq(%w[0 1])
    end

    it "restricts the serialized files to `only:` without touching the test list" do
      map.record("spec/a_spec.rb:1", lib_file => 0b1, other_file => 0b1)

      restricted = map.to_h(only: Set[lib_file])

      expect(restricted["files"].keys).to eq([lib_file])
      expect(restricted["contexts"]).to eq(["spec/a_spec.rb:1"])
    end

    it "collapses a duplicated test id in the serialized list to one entry" do
      restored = described_class.from_hash(
        "version" => 1,
        "contexts" => ["spec/a_spec.rb:1", "spec/a_spec.rb:1"],
        "files" => {lib_file => {"0" => "1", "1" => "2"}}
      )

      expect(restored.contexts).to eq(["spec/a_spec.rb:1"])
      expect(restored.covering(lib_file, 2)).to eq(["spec/a_spec.rb:1"])
    end

    # All-or-nothing: a partially salvaged map would answer `covering`
    # queries with silent gaps, and the merge already treats an absent map
    # correctly (it drops the merged map consistently).
    it "rejects every malformed shape as nil" do
      valid_files = {lib_file => {"0" => "1"}}

      [
        nil,
        "junk",
        {"contexts" => "junk", "files" => valid_files},
        {"contexts" => ["a", :b], "files" => valid_files},
        {"contexts" => ["a"], "files" => "junk"},
        {"contexts" => ["a"], "files" => {lib_file => "junk"}},
        {"contexts" => ["a"], "files" => {sym: {"0" => "1"}}},
        {"contexts" => ["a"], "files" => {lib_file => {0 => "1"}}},
        {"contexts" => ["a"], "files" => {lib_file => {"x" => "1"}}},
        {"contexts" => ["a"], "files" => {lib_file => {"1" => "1"}}},
        {"contexts" => ["a"], "files" => {lib_file => {"0" => 1}}},
        {"contexts" => ["a"], "files" => {lib_file => {"0" => "xyz"}}}
      ].each do |malformed|
        # Versioned so each input fails on the validation it targets, not
        # at the version gate.
        malformed = malformed.merge("version" => 1) if malformed.is_a?(Hash)
        expect(described_class.from_hash(malformed)).to be_nil, "expected nil for #{malformed.inspect}"
      end
    end
  end
end
