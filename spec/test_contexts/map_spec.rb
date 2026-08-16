# frozen_string_literal: true

require "helper"
require "simplecov/test_contexts/map"

RSpec.describe SimpleCov::TestContexts::Map do
  let(:hash) do
    {
      "version" => 1,
      "tests" => [["./spec/a_spec.rb[1:1]", "A does one thing"], ["FooTest#test_save", "FooTest#test_save"]],
      "files" => {
        "/proj/lib/a.rb" => {"0" => "6", "1" => "16"},
        "/proj/lib/b.rb" => {"1" => "1"}
      }
    }
  end
  let(:map) { described_class.from_hash(hash) }

  describe ".from_hash" do
    it "round-trips through to_h" do
      expect(map.to_h).to eq hash
    end

    it "rejects a non-hash payload" do
      expect(described_class.from_hash(nil)).to be_nil
      expect(described_class.from_hash([])).to be_nil
    end

    it "rejects an unknown version" do
      expect(described_class.from_hash(hash.merge("version" => 2))).to be_nil
    end

    it "rejects a tests table that is not an array of string pairs" do
      expect(described_class.from_hash(hash.merge("tests" => nil))).to be_nil
      expect(described_class.from_hash(hash.merge("tests" => [["only-id"]]))).to be_nil
      expect(described_class.from_hash(hash.merge("tests" => [["id", 42]]))).to be_nil
    end

    it "rejects files that are not a hash of hashes" do
      expect(described_class.from_hash(hash.merge("files" => nil))).to be_nil
      expect(described_class.from_hash(hash.merge("files" => {"/proj/lib/a.rb" => []}))).to be_nil
    end

    it "rejects a non-string file path" do
      expect(described_class.from_hash(hash.merge("files" => {1 => {"0" => "1"}}))).to be_nil
    end

    it "rejects malformed test indices" do
      expect(described_class.from_hash(hash.merge("files" => {"/proj/lib/a.rb" => {"01" => "1"}}))).to be_nil
      expect(described_class.from_hash(hash.merge("files" => {"/proj/lib/a.rb" => {1 => "1"}}))).to be_nil
    end

    it "rejects an index pointing past the tests table" do
      expect(described_class.from_hash(hash.merge("files" => {"/proj/lib/a.rb" => {"2" => "1"}}))).to be_nil
    end

    it "rejects malformed masks" do
      expect(described_class.from_hash(hash.merge("files" => {"/proj/lib/a.rb" => {"0" => "XYZ"}}))).to be_nil
      expect(described_class.from_hash(hash.merge("files" => {"/proj/lib/a.rb" => {"0" => ""}}))).to be_nil
      expect(described_class.from_hash(hash.merge("files" => {"/proj/lib/a.rb" => {"0" => 6}}))).to be_nil
    end
  end

  describe "#tests_for" do
    it "names the tests whose bitmap covers the line, in table order" do
      # 0x6 = lines 2 and 3; 0x16 = lines 2, 3 and 5
      expect(map.tests_for("/proj/lib/a.rb", 2)).to eq [
        ["./spec/a_spec.rb[1:1]", "A does one thing"],
        ["FooTest#test_save", "FooTest#test_save"]
      ]
      expect(map.tests_for("/proj/lib/a.rb", 5)).to eq [["FooTest#test_save", "FooTest#test_save"]]
    end

    it "answers an empty list for an uncovered line" do
      expect(map.tests_for("/proj/lib/a.rb", 1)).to be_empty
      expect(map.tests_for("/proj/lib/a.rb", 999)).to be_empty
    end

    it "answers an empty list for an unknown file" do
      expect(map.tests_for("/proj/lib/unknown.rb", 1)).to be_empty
    end

    it "answers an empty list for a non-positive line number" do
      expect(map.tests_for("/proj/lib/a.rb", 0)).to be_empty
    end
  end

  describe "#bitmaps_for" do
    it "exposes the file's test-index => bitmap mapping" do
      expect(map.bitmaps_for("/proj/lib/b.rb")).to eq(1 => 1)
    end

    it "is empty for an unknown file" do
      expect(map.bitmaps_for("/proj/lib/unknown.rb")).to eq({})
    end
  end

  describe "#slice" do
    it "narrows the files but keeps the whole tests table" do
      sliced = map.slice(["/proj/lib/b.rb"])

      expect(sliced.to_h["files"].keys).to eq ["/proj/lib/b.rb"]
      expect(sliced.tests.size).to eq 2
      expect(sliced.tests_for("/proj/lib/b.rb", 1)).to eq [["FooTest#test_save", "FooTest#test_save"]]
    end
  end

  describe "#to_h" do
    it "drops zero bitmaps and files left without any" do
      sparse = described_class.new(
        tests: [%w[a a]],
        files: {"/proj/lib/a.rb" => {0 => 0}, "/proj/lib/b.rb" => {0 => 5}}
      )

      expect(sparse.to_h["files"]).to eq("/proj/lib/b.rb" => {"0" => "5"})
    end
  end
end
