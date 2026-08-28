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

    # The two recordings share line 3 on purpose: a union keeps a line
    # both of them saw, where any other bitwise fold would cancel or
    # discard it.
    it "keeps a line two recordings of one test both covered" do
      map.record("spec/thing_spec.rb:5", lib_file => 0b101)
      map.record("spec/thing_spec.rb:5", lib_file => 0b110)

      expect(map.serialized_bitmaps_for(lib_file)).to eq("0" => "7")
    end

    # A file with nothing to record is skipped, not a full stop: the
    # rest of the batch still has to land.
    it "records the rest of a batch after a file the context never touched" do
      map.record("spec/thing_spec.rb:5", lib_file => 0, other_file => 0b1)

      expect(map.covering(other_file, 1)).to eq(["spec/thing_spec.rb:5"])
    end

    it "answers itself, so recordings chain" do
      expect(map.record("spec/thing_spec.rb:5", lib_file => 0b1)).to be(map)
    end

    # Callers hand in project-relative paths, and the project root is not
    # necessarily the working directory (`simplecov merge` runs from
    # wherever the user is).
    it "resolves a relative path against SimpleCov.root, not the working directory" do
      map.record("spec/thing_spec.rb:5", lib_file => 0b1)

      Dir.mktmpdir do |elsewhere|
        Dir.chdir(elsewhere) do
          expect(map.covering("lib/thing.rb", 1)).to eq(["spec/thing_spec.rb:5"])
          expect(map.serialized_bitmaps_for("lib/thing.rb")).to eq("0" => "1")
        end
      end
    end

    it "keeps a test that covered nothing, without inventing file entries" do
      map.record("spec/quiet_spec.rb:1", {})
      map.record("spec/zero_spec.rb:2", lib_file => 0)

      expect(map.contexts).to eq(["spec/quiet_spec.rb:1", "spec/zero_spec.rb:2"])
      expect(map.to_h["files"]).to eq({})
    end
  end

  describe "#contexts" do
    it "answers a copy, so a caller cannot edit the recorded list" do
      map.record("spec/thing_spec.rb:5", {})

      map.contexts << "spec/injected_spec.rb:1"

      expect(map.contexts).to eq(["spec/thing_spec.rb:5"])
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

    # Both sides recorded line 1 for the same test, which is what one
    # test running under two workers looks like: the union keeps it.
    it "keeps a line both maps recorded for the same test" do
      map.record("spec/a_spec.rb:1", lib_file => 0b1)
      other = described_class.new
      other.record("spec/a_spec.rb:1", lib_file => 0b1)

      map.absorb(other)

      expect(map.covering(lib_file, 1)).to eq(["spec/a_spec.rb:1"])
    end

    it "takes on a file it had never recorded itself" do
      map.record("spec/a_spec.rb:1", lib_file => 0b1)
      other = described_class.new
      other.record("spec/b_spec.rb:2", other_file => 0b10)

      map.absorb(other)

      expect(map.covering(other_file, 2)).to eq(["spec/b_spec.rb:2"])
    end

    it "answers itself, so absorbs chain" do
      expect(map.absorb(described_class.new)).to be(map)
    end
  end

  describe "#serialized_bitmaps_for" do
    it "serializes one file's table in the wire encoding, index-sorted" do
      map.record("spec/b_spec.rb:2", {})
      map.record("spec/a_spec.rb:1", lib_file => 0xff)
      map.record("spec/b_spec.rb:2", lib_file => 0b1)

      expect(map.serialized_bitmaps_for(lib_file)).to eq("0" => "1", "1" => "ff")
    end

    it "resolves project-relative paths and answers an empty table for an untouched file" do
      map.record("spec/a_spec.rb:1", lib_file => 0b1)

      expect(map.serialized_bitmaps_for("lib/thing.rb")).to eq("0" => "1")
      expect(map.serialized_bitmaps_for(other_file)).to eq({})
    end

    # The project root is not necessarily the working directory
    # (`simplecov merge` runs from wherever the user is), so a relative
    # path has to resolve against the root and nothing else.
    it "resolves a relative path against SimpleCov.root, not the working directory" do
      map.record("spec/a_spec.rb:1", lib_file => 0b1)

      Dir.mktmpdir do |elsewhere|
        Dir.chdir(elsewhere) do
          expect(map.serialized_bitmaps_for("lib/thing.rb")).to eq("0" => "1")
        end
      end
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

    it "answers a copy of the context list, so a caller cannot edit the map" do
      map.record("spec/a_spec.rb:1", lib_file => 0b1)

      map.to_h["contexts"] << "spec/injected_spec.rb:1"

      expect(map.contexts).to eq(["spec/a_spec.rb:1"])
    end

    # A test that covered nothing has no entry in any file table, so the
    # serialized context list is the only record that it ran at all.
    it "restores a test that covered nothing, in its recorded position" do
      map.record("spec/quiet_spec.rb:1", {})
      map.record("spec/a_spec.rb:1", lib_file => 0b1)

      restored = described_class.from_hash(map.to_h)

      expect(restored.contexts).to eq(["spec/quiet_spec.rb:1", "spec/a_spec.rb:1"])
      expect(restored.covering(lib_file, 1)).to eq(["spec/a_spec.rb:1"])
    end

    # A bitmap wide enough to need more than one hex digit, read back as
    # hexadecimal rather than as decimal.
    it "round-trips a multi-digit hex bitmap" do
      map.record("spec/a_spec.rb:1", lib_file => 0xff)

      restored = described_class.from_hash(map.to_h)

      expect(restored.covering(lib_file, 8)).to eq(["spec/a_spec.rb:1"])
      expect(restored.serialized_bitmaps_for(lib_file)).to eq("0" => "ff")
    end

    # An index wide enough to need more than one decimal digit, which a
    # suite of more than ten tests reaches immediately.
    it "reads a context index past the first ten" do
      contexts = Array.new(11) { |index| "spec/t#{index}_spec.rb:1" }

      restored = described_class.from_hash(
        "version" => 1, "contexts" => contexts, "files" => {lib_file => {"10" => "1"}}
      )

      expect(restored.covering(lib_file, 1)).to eq(["spec/t10_spec.rb:1"])
    end

    # A decimal index, whatever padding the writer gave it: "010" is index
    # ten, the way every other reader of this format would take it.
    it "reads a context index written with a leading zero" do
      contexts = Array.new(11) { |index| "spec/t#{index}_spec.rb:1" }

      restored = described_class.from_hash(
        "version" => 1, "contexts" => contexts, "files" => {lib_file => {"010" => "1"}}
      )

      expect(restored.covering(lib_file, 1)).to eq(["spec/t10_spec.rb:1"])
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
    def expect_rejected(shapes)
      shapes.each do |shape|
        # Versioned so each input fails on the validation it targets, not
        # at the version gate.
        malformed = shape.is_a?(Hash) ? shape.merge("version" => 1) : shape
        expect(described_class.from_hash(malformed)).to be_nil, "expected nil for #{malformed.inspect}"
      end
    end

    it "rejects a malformed envelope as nil" do
      valid_files = {lib_file => {"0" => "1"}}

      expect_rejected(
        [
          nil,
          "junk",
          # An Array rather than another String: a String answers nil to a
          # String subscript, so it cannot tell a dropped Hash check apart
          # from a missing version.
          [1, 2],
          {"files" => valid_files},
          {"contexts" => ["a"]},
          {"contexts" => "junk", "files" => valid_files},
          {"contexts" => ["a", :b], "files" => valid_files},
          {"contexts" => ["a"], "files" => "junk"},
          {"contexts" => ["a"], "files" => {lib_file => "junk"}},
          {"contexts" => ["a"], "files" => {sym: {"0" => "1"}}}
        ]
      )
    end

    it "rejects a malformed file table as nil" do
      expect_rejected(
        [
          {"contexts" => ["a"], "files" => {lib_file => {0 => "1"}}},
          {"contexts" => ["a"], "files" => {lib_file => {"x" => "1"}}},
          {"contexts" => ["a"], "files" => {lib_file => {"" => "1"}}},
          {"contexts" => ["a"], "files" => {lib_file => {"x0" => "1"}}},
          {"contexts" => %w[a b], "files" => {lib_file => {"1x" => "1"}}},
          # A trailing newline is not part of a decimal index, nor of a
          # bitmap: both are anchored at the very end of the string.
          {"contexts" => %w[a b], "files" => {lib_file => {"1\n" => "1"}}},
          {"contexts" => ["a"], "files" => {lib_file => {"0" => "1\n"}}},
          {"contexts" => ["a"], "files" => {lib_file => {"1" => "1"}}},
          {"contexts" => ["a"], "files" => {lib_file => {"0" => 1}}},
          {"contexts" => ["a"], "files" => {lib_file => {"0" => ""}}},
          {"contexts" => ["a"], "files" => {lib_file => {"0" => "z1"}}},
          {"contexts" => ["a"], "files" => {lib_file => {"0" => "1z"}}},
          {"contexts" => ["a"], "files" => {lib_file => {"0" => "xyz"}}}
        ]
      )
    end
  end
end
