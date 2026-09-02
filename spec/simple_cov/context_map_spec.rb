# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ContextMap do
  subject(:map) { described_class.new }

  def lib_file = File.join(SimpleCov.root, "lib/thing.rb")

  def other_file = File.join(SimpleCov.root, "lib/other.rb")

  def from_another_directory
    Dir.mktmpdir do |elsewhere|
      Dir.chdir(elsewhere) { yield }
    end
  end

  describe "#record and #covering" do
    context "with two tests recorded" do
      before do
        map.record("spec/thing_spec.rb:5", lib_file => 0b101)
        map.record("spec/other_spec.rb:9", lib_file => 0b100, other_file => 0b1)
      end

      it "attributes a line only one test reached to that test" do
        expect(map.covering(lib_file, 1)).to eq(["spec/thing_spec.rb:5"])
      end

      it "attributes a line both tests reached to both" do
        expect(map.covering(lib_file, 3)).to eq(["spec/other_spec.rb:9", "spec/thing_spec.rb:5"])
      end

      it "attributes the second file's line to the test that reached it" do
        expect(map.covering(other_file, 1)).to eq(["spec/other_spec.rb:9"])
      end
    end

    it "resolves project-relative paths against SimpleCov.root" do
      map.record("spec/thing_spec.rb:5", lib_file => 0b1)

      expect(map.covering("lib/thing.rb", 1)).to eq(["spec/thing_spec.rb:5"])
    end

    it "answers an empty list for an untouched line" do
      map.record("spec/thing_spec.rb:5", lib_file => 0b1)

      expect(map.covering(lib_file, 2)).to eq([])
    end

    it "answers an empty list for an unknown file" do
      map.record("spec/thing_spec.rb:5", lib_file => 0b1)

      expect(map.covering(other_file, 1)).to eq([])
    end

    it "answers an empty list for a nonsense line number" do
      map.record("spec/thing_spec.rb:5", lib_file => 0b1)

      expect(map.covering(lib_file, 0)).to eq([])
    end

    context "with a test recorded more than once" do
      before do
        map.record("spec/thing_spec.rb:5", lib_file => 0b1)
        map.record("spec/thing_spec.rb:5", lib_file => 0b10)
      end

      it "keeps the line of the first recording" do
        expect(map.covering(lib_file, 1)).to eq(["spec/thing_spec.rb:5"])
      end

      it "keeps the line of the second recording" do
        expect(map.covering(lib_file, 2)).to eq(["spec/thing_spec.rb:5"])
      end

      it "lists the test once" do
        expect(map.contexts).to eq(["spec/thing_spec.rb:5"])
      end
    end

    it "keeps a line two recordings of one test both covered" do
      map.record("spec/thing_spec.rb:5", lib_file => 0b101)
      map.record("spec/thing_spec.rb:5", lib_file => 0b110)

      expect(map.serialized_bitmaps_for(lib_file)).to eq("0" => "7")
    end

    it "records the rest of a batch after a file the context never touched" do
      map.record("spec/thing_spec.rb:5", lib_file => 0, other_file => 0b1)

      expect(map.covering(other_file, 1)).to eq(["spec/thing_spec.rb:5"])
    end

    it "answers itself, so recordings chain" do
      expect(map.record("spec/thing_spec.rb:5", lib_file => 0b1)).to be(map)
    end

    it "resolves a covering lookup against SimpleCov.root, not the working directory" do
      map.record("spec/thing_spec.rb:5", lib_file => 0b1)

      expect(from_another_directory { map.covering("lib/thing.rb", 1) }).to eq(["spec/thing_spec.rb:5"])
    end

    it "resolves a serialization lookup against SimpleCov.root, not the working directory" do
      map.record("spec/thing_spec.rb:5", lib_file => 0b1)

      expect(from_another_directory { map.serialized_bitmaps_for("lib/thing.rb") }).to eq("0" => "1")
    end

    it "keeps a test that covered nothing" do
      map.record("spec/quiet_spec.rb:1", {})
      map.record("spec/zero_spec.rb:2", lib_file => 0)

      expect(map.contexts).to eq(["spec/quiet_spec.rb:1", "spec/zero_spec.rb:2"])
    end

    it "invents no file entries for a test that covered nothing" do
      map.record("spec/quiet_spec.rb:1", {})
      map.record("spec/zero_spec.rb:2", lib_file => 0)

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
    end

    it "is no longer empty once a test is recorded" do
      map.record("spec/thing_spec.rb:5", {})

      expect(map).not_to be_empty
    end
  end

  describe "#absorb" do
    let(:other) { described_class.new }

    context "with a map that shares a test id" do
      before do
        map.record("spec/a_spec.rb:1", lib_file => 0b1)
        other.record("spec/b_spec.rb:2", lib_file => 0b10)
        other.record("spec/a_spec.rb:1", lib_file => 0b100)

        map.absorb(other)
      end

      it "keeps its own line for the shared test" do
        expect(map.covering(lib_file, 1)).to eq(["spec/a_spec.rb:1"])
      end

      it "takes on the other map's line for the other map's test" do
        expect(map.covering(lib_file, 2)).to eq(["spec/b_spec.rb:2"])
      end

      it "re-interns the other map's index for the shared test" do
        expect(map.covering(lib_file, 3)).to eq(["spec/a_spec.rb:1"])
      end

      it "merges the test lists by id" do
        expect(map.contexts).to eq(["spec/a_spec.rb:1", "spec/b_spec.rb:2"])
      end
    end

    it "keeps a line both maps recorded for the same test" do
      map.record("spec/a_spec.rb:1", lib_file => 0b1)
      other.record("spec/a_spec.rb:1", lib_file => 0b1)

      map.absorb(other)

      expect(map.covering(lib_file, 1)).to eq(["spec/a_spec.rb:1"])
    end

    it "takes on a file it had never recorded itself" do
      map.record("spec/a_spec.rb:1", lib_file => 0b1)
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

    it "resolves project-relative paths" do
      map.record("spec/a_spec.rb:1", lib_file => 0b1)

      expect(map.serialized_bitmaps_for("lib/thing.rb")).to eq("0" => "1")
    end

    it "answers an empty table for an untouched file" do
      map.record("spec/a_spec.rb:1", lib_file => 0b1)

      expect(map.serialized_bitmaps_for(other_file)).to eq({})
    end

    it "resolves a relative path against SimpleCov.root, not the working directory" do
      map.record("spec/a_spec.rb:1", lib_file => 0b1)

      expect(from_another_directory { map.serialized_bitmaps_for("lib/thing.rb") }).to eq("0" => "1")
    end
  end

  describe "#to_h and .from_hash" do
    let(:serialized_form) do
      {
        "version" => 1,
        "contexts" => ["spec/a_spec.rb:1", "spec/b_spec.rb:2"],
        "files" => {lib_file => {"0" => "1", "1" => "ff"}}
      }
    end

    let(:valid_files) { {lib_file => {"0" => "1"}} }

    def malformed_envelopes
      [
        nil,
        "junk",
        [1, 2],
        {"files" => valid_files},
        {"contexts" => ["a"]},
        {"contexts" => "junk", "files" => valid_files},
        {"contexts" => ["a", :b], "files" => valid_files},
        {"contexts" => ["a"], "files" => "junk"},
        {"contexts" => ["a"], "files" => {lib_file => "junk"}},
        {"contexts" => ["a"], "files" => {sym: {"0" => "1"}}}
      ]
    end

    def malformed_file_tables
      [
        {"contexts" => ["a"], "files" => {lib_file => {0 => "1"}}},
        {"contexts" => ["a"], "files" => {lib_file => {"x" => "1"}}},
        {"contexts" => ["a"], "files" => {lib_file => {"" => "1"}}},
        {"contexts" => ["a"], "files" => {lib_file => {"x0" => "1"}}},
        {"contexts" => %w[a b], "files" => {lib_file => {"1x" => "1"}}},
        {"contexts" => %w[a b], "files" => {lib_file => {"1\n" => "1"}}},
        {"contexts" => ["a"], "files" => {lib_file => {"0" => "1\n"}}},
        {"contexts" => ["a"], "files" => {lib_file => {"1" => "1"}}},
        {"contexts" => ["a"], "files" => {lib_file => {"0" => 1}}},
        {"contexts" => ["a"], "files" => {lib_file => {"0" => ""}}},
        {"contexts" => ["a"], "files" => {lib_file => {"0" => "z1"}}},
        {"contexts" => ["a"], "files" => {lib_file => {"0" => "1z"}}},
        {"contexts" => ["a"], "files" => {lib_file => {"0" => "xyz"}}}
      ]
    end

    context "with two tests recorded across two files" do
      let(:restored) { described_class.from_hash(map.to_h) }

      before do
        map.record("spec/a_spec.rb:1", lib_file => 0b101)
        map.record("spec/b_spec.rb:2", other_file => 0b1)
      end

      it "round-trips through the serialized form" do
        expect(restored.to_h).to eq(map.to_h)
      end

      it "round-trips the attribution" do
        expect(restored.covering(lib_file, 3)).to eq(["spec/a_spec.rb:1"])
      end
    end

    it "serializes bitmaps as hex keyed by interned test index, under a format version" do
      map.record("spec/a_spec.rb:1", lib_file => 0b1)
      map.record("spec/b_spec.rb:2", lib_file => 0xff)

      expect(map.to_h).to eq(serialized_form)
    end

    it "treats a format version it does not know as no map at all" do
      map.record("spec/a_spec.rb:1", lib_file => 0b1)

      expect(described_class.from_hash(map.to_h.merge("version" => 2))).to be_nil
    end

    it "treats a missing format version as no map at all" do
      map.record("spec/a_spec.rb:1", lib_file => 0b1)

      expect(described_class.from_hash(map.to_h.except("version"))).to be_nil
    end

    context "with a file first recorded by an absorbed map" do
      let(:other_map) { described_class.new }

      before do
        map.record("spec/b_spec.rb:2", {})
        map.record("spec/a_spec.rb:1", {})
        other_map.record("spec/a_spec.rb:1", lib_file => 0b1)
        other_map.record("spec/b_spec.rb:2", lib_file => 0b10)
        map.absorb(other_map)
      end

      it "serializes each file's bitmaps in test-index order" do
        expect(map.to_h["files"][lib_file].keys).to eq(%w[0 1])
      end
    end

    it "restricts the serialized files to `only:`" do
      map.record("spec/a_spec.rb:1", lib_file => 0b1, other_file => 0b1)

      expect(map.to_h(only: Set[lib_file])["files"].keys).to eq([lib_file])
    end

    it "leaves the test list alone when `only:` restricts the files" do
      map.record("spec/a_spec.rb:1", lib_file => 0b1, other_file => 0b1)

      expect(map.to_h(only: Set[lib_file])["contexts"]).to eq(["spec/a_spec.rb:1"])
    end

    it "answers a copy of the context list, so a caller cannot edit the map" do
      map.record("spec/a_spec.rb:1", lib_file => 0b1)

      map.to_h["contexts"] << "spec/injected_spec.rb:1"

      expect(map.contexts).to eq(["spec/a_spec.rb:1"])
    end

    context "with a test that covered nothing recorded first" do
      let(:restored) { described_class.from_hash(map.to_h) }

      before do
        map.record("spec/quiet_spec.rb:1", {})
        map.record("spec/a_spec.rb:1", lib_file => 0b1)
      end

      it "restores it in its recorded position" do
        expect(restored.contexts).to eq(["spec/quiet_spec.rb:1", "spec/a_spec.rb:1"])
      end

      it "restores the other test's attribution" do
        expect(restored.covering(lib_file, 1)).to eq(["spec/a_spec.rb:1"])
      end
    end

    context "with a multi-digit hex bitmap" do
      let(:restored) { described_class.from_hash(map.to_h) }

      before { map.record("spec/a_spec.rb:1", lib_file => 0xff) }

      it "round-trips its attribution" do
        expect(restored.covering(lib_file, 8)).to eq(["spec/a_spec.rb:1"])
      end

      it "round-trips its serialized form" do
        expect(restored.serialized_bitmaps_for(lib_file)).to eq("0" => "ff")
      end
    end

    it "reads a context index past the first ten" do
      contexts = Array.new(11) { |index| "spec/t#{index}_spec.rb:1" }

      restored = described_class.from_hash(
        "version" => 1, "contexts" => contexts, "files" => {lib_file => {"10" => "1"}}
      )

      expect(restored.covering(lib_file, 1)).to eq(["spec/t10_spec.rb:1"])
    end

    it "reads a context index written with a leading zero" do
      contexts = Array.new(11) { |index| "spec/t#{index}_spec.rb:1" }

      restored = described_class.from_hash(
        "version" => 1, "contexts" => contexts, "files" => {lib_file => {"010" => "1"}}
      )

      expect(restored.covering(lib_file, 1)).to eq(["spec/t10_spec.rb:1"])
    end

    context "with a duplicated test id in the serialized list" do
      let(:restored) do
        described_class.from_hash(
          "version" => 1,
          "contexts" => ["spec/a_spec.rb:1", "spec/a_spec.rb:1"],
          "files" => {lib_file => {"0" => "1", "1" => "2"}}
        )
      end

      it "collapses the list to one entry" do
        expect(restored.contexts).to eq(["spec/a_spec.rb:1"])
      end

      it "keeps the bitmap of the second index" do
        expect(restored.covering(lib_file, 2)).to eq(["spec/a_spec.rb:1"])
      end
    end

    def expect_rejected(shapes)
      shapes.each do |shape|
        malformed = shape.is_a?(Hash) ? shape.merge("version" => 1) : shape
        expect(described_class.from_hash(malformed)).to be_nil, "expected nil for #{malformed.inspect}"
      end
    end

    it "rejects a malformed envelope as nil" do
      expect_rejected(malformed_envelopes)
    end

    it "rejects a malformed file table as nil" do
      expect_rejected(malformed_file_tables)
    end
  end
end
