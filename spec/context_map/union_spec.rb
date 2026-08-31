# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ContextMap::Union do
  subject(:union) { described_class.new }

  let(:lib_file) { File.join(SimpleCov.root, "lib/thing.rb") }

  def map_entry(test_id, bitmap)
    map = SimpleCov::ContextMap.new
    map.record(test_id, lib_file => bitmap)
    {"contexts" => map.to_h}
  end

  describe "#map" do
    it "unions the maps when every entry carries one" do
      union.absorb_resultset("RSpec" => map_entry("spec/a_spec.rb:1", 0b1))
      union.absorb_resultset("Cucumber" => map_entry("spec/b_spec.rb:2", 0b10))

      expect(union).to be_complete
      expect(union.map.covering(lib_file, 1)).to eq(["spec/a_spec.rb:1"])
      expect(union.map.covering(lib_file, 2)).to eq(["spec/b_spec.rb:2"])
    end

    it "treats an empty map as recorded, so a tracked suite that ran nothing keeps the union" do
      union.absorb_resultset("RSpec" => map_entry("spec/a_spec.rb:1", 0b1),
                             "Idle" => {"contexts" => SimpleCov::ContextMap.new.to_h})

      expect(union.map.contexts).to eq(["spec/a_spec.rb:1"])
    end

    it "drops the union out loud when only some entries carry a map" do
      union.absorb_resultset("RSpec" => map_entry("spec/a_spec.rb:1", 0b1))
      union.absorb_resultset("Cucumber" => {})

      output = capture_stderr { expect(union.map).to be_nil }

      expect(union).not_to be_complete
      expect(output).to include("Dropped the per-test map", "1 of 2 merged results")
    end

    it "treats a malformed map the same as an absent one" do
      union.absorb_resultset("RSpec" => {"contexts" => "junk"})

      expect(union).not_to be_complete
    end

    it "stays quiet about the drop when print_errors is off" do
      union.absorb_entry(map_entry("spec/a_spec.rb:1", 0b1))
      union.absorb_entry({})

      allow(SimpleCov).to receive(:print_errors).and_return(false)

      output = capture_stderr { expect(union.map).to be_nil }

      expect(output).to be_empty
    end

    it "stays quiet when nothing recorded a map at all" do
      union.absorb_resultset("RSpec" => {}, "Cucumber" => {})

      output = capture_stderr { expect(union.map).to be_nil }

      expect(output).to be_empty
    end
  end

  describe "#collector" do
    it "absorbs each resultset handed to the merge" do
      union.collector.call("RSpec" => map_entry("spec/a_spec.rb:1", 0b1))

      expect(union.entries).to eq(1)
      expect(union.carrying).to eq(1)
    end
  end

  describe "#absorb_union" do
    it "folds another union's counts, completeness, and map in" do
      union.absorb_entry(map_entry("spec/a_spec.rb:1", 0b1))
      other = described_class.new
      other.absorb_entry(map_entry("spec/b_spec.rb:2", 0b10))

      union.absorb_union(other)

      expect(union.entries).to eq(2)
      expect(union.carrying).to eq(2)
      expect(union.map.contexts).to contain_exactly("spec/a_spec.rb:1", "spec/b_spec.rb:2")
    end

    it "adds the other union's totals to its own" do
      union.absorb_entry(map_entry("spec/a_spec.rb:1", 0b1))
      other = described_class.new
      other.absorb_entry(map_entry("spec/b_spec.rb:2", 0b10))
      other.absorb_entry(map_entry("spec/c_spec.rb:3", 0b100))
      other.absorb_entry({})

      union.absorb_union(other)

      expect(union.entries).to eq(4)
      expect(union.carrying).to eq(3)
    end

    it "goes incomplete when the absorbed union is incomplete" do
      union.absorb_entry(map_entry("spec/a_spec.rb:1", 0b1))
      other = described_class.new
      other.absorb_entry({})

      union.absorb_union(other)

      expect(union).not_to be_complete
    end

    it "stays incomplete once it is, whatever the absorbed union carries" do
      union.absorb_entry({})
      other = described_class.new
      other.absorb_entry(map_entry("spec/a_spec.rb:1", 0b1))

      union.absorb_union(other)

      expect(union).not_to be_complete
    end

    it "answers itself, so unions chain" do
      expect(union.absorb_union(described_class.new)).to be(union)
    end
  end
end
