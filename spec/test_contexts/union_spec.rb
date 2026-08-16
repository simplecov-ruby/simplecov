# frozen_string_literal: true

require "helper"
require "simplecov/test_contexts/union"

RSpec.describe SimpleCov::TestContexts::Union do
  subject(:union) { described_class.new }

  let(:first_contexts) do
    {
      "version" => 1,
      "tests" => [%w[a1 a1], %w[shared shared]],
      "files" => {"/proj/a.rb" => {"0" => "1", "1" => "4"}}
    }
  end
  let(:second_contexts) do
    {
      "version" => 1,
      # the shared test sits at a different local index here
      "tests" => [%w[shared shared], %w[b1 b1]],
      "files" => {"/proj/a.rb" => {"0" => "2"}, "/proj/b.rb" => {"1" => "8"}}
    }
  end

  def entry(contexts)
    {"coverage" => {}, "timestamp" => Time.now.to_f}.tap do |data|
      data["test_contexts"] = contexts if contexts
    end
  end

  describe "#observe" do
    it "unions recordings, re-interning tests by their rerun id" do
      union.observe("first" => entry(first_contexts))
      union.observe("second" => entry(second_contexts))

      merged = union.result
      expect(merged.tests).to eq [%w[a1 a1], %w[shared shared], %w[b1 b1]]
      # shared covered line 3 in the first entry (0x4) and line 2 in the second (0x2)
      expect(merged.bitmaps_for("/proj/a.rb")).to eq(0 => 1, 1 => 0x6)
      expect(merged.bitmaps_for("/proj/b.rb")).to eq(2 => 8)
    end

    it "drops the recording when any entry lacks one" do
      union.observe("first" => entry(first_contexts), "second" => entry(nil))

      expect(union.result).to be_nil
    end

    it "drops the recording when an entry's payload is malformed" do
      union.observe("first" => entry("version" => 99))

      expect(union.result).to be_nil
    end

    it "has no recording when nothing was observed" do
      expect(union.result).to be_nil
    end

    it "keeps an empty-but-present recording" do
      union.observe("first" => entry("version" => 1, "tests" => [], "files" => {}))

      expect(union.result).not_to be_nil
      expect(union.result.to_h).to eq("version" => 1, "tests" => [], "files" => {})
    end
  end

  describe "#result_with_drop_warning" do
    it "warns once when a mixed union dropped the recording" do
      union.observe("first" => entry(first_contexts), "second" => entry(nil))

      stderr = capture_stderr do
        expect(union.result_with_drop_warning).to be_nil
        union.result_with_drop_warning
      end

      expect(union).to be_dropped_mixed
      expect(stderr.scan("drops it").size).to eq 1
    end

    it "stays silent when nothing carried a recording at all" do
      union.observe("first" => entry(nil))

      stderr = capture_stderr { expect(union.result_with_drop_warning).to be_nil }

      expect(union).not_to be_dropped_mixed
      expect(stderr).to be_empty
    end

    it "stays silent for a complete union" do
      union.observe("first" => entry(first_contexts))

      stderr = capture_stderr { expect(union.result_with_drop_warning).not_to be_nil }

      expect(stderr).to be_empty
    end

    it "respects print_errors" do
      allow(SimpleCov).to receive(:print_errors).and_return(false)
      union.observe("first" => entry(first_contexts), "second" => entry(nil))

      stderr = capture_stderr { union.result_with_drop_warning }

      expect(stderr).to be_empty
    end
  end

  describe "#dump and #absorb_dump" do
    it "round-trips a complete recording through the pipe payload" do
      union.observe("first" => entry(first_contexts))

      other = described_class.new
      other.absorb_dump(union.dump)

      expect(other.result.to_h).to eq union.result.to_h
    end

    it "propagates incompleteness" do
      union.observe("first" => entry(nil))

      other = described_class.new
      other.absorb_dump(union.dump)
      other.absorb_entry(entry(first_contexts))

      expect(other.result).to be_nil
    end

    it "treats an empty slice as vacuously complete" do
      other = described_class.new
      other.absorb_dump(union.dump)
      other.absorb_entry(entry(first_contexts))

      expect(other.result).not_to be_nil
    end

    it "marks incomplete when a payload no longer parses" do
      other = described_class.new
      other.absorb_dump([false, {"version" => 99}])

      expect(other.result).to be_nil
    end
  end

  describe ".carry" do
    let(:merged) { {"coverage" => {}, "timestamp" => 1.0, "test_contexts" => second_contexts} }

    it "unions both recordings when both entries carry one" do
      carried = described_class.carry(merged, entry(first_contexts), entry(second_contexts))

      expect(carried["test_contexts"]["tests"]).to eq [%w[a1 a1], %w[shared shared], %w[b1 b1]]
      expect(carried["test_contexts"]["files"]["/proj/a.rb"]).to eq("0" => "1", "1" => "6")
    end

    it "removes the key with a warning when either entry lacks a recording" do
      carried = nil
      stderr = capture_stderr { carried = described_class.carry(merged, entry(nil), entry(second_contexts)) }

      expect(carried).not_to have_key("test_contexts")
      expect(carried["coverage"]).to eq({})
      expect(stderr).to include("the merged result drops it")
    end

    it "stays silent when neither concurrent entry recorded" do
      stderr = capture_stderr { described_class.carry(merged, entry(nil), entry(nil)) }

      expect(stderr).to be_empty
    end
  end
end
