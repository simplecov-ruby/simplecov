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
    context "when every entry carries a map" do
      before do
        union.absorb_resultset("RSpec" => map_entry("spec/a_spec.rb:1", 0b1))
        union.absorb_resultset("Cucumber" => map_entry("spec/b_spec.rb:2", 0b10))
      end

      it "is complete" do
        expect(union).to be_complete
      end

      it "keeps the first entry's attribution" do
        expect(union.map.covering(lib_file, 1)).to eq(["spec/a_spec.rb:1"])
      end

      it "keeps the second entry's attribution" do
        expect(union.map.covering(lib_file, 2)).to eq(["spec/b_spec.rb:2"])
      end
    end

    it "treats an empty map as recorded, so a tracked suite that ran nothing keeps the union" do
      union.absorb_resultset("RSpec" => map_entry("spec/a_spec.rb:1", 0b1),
        "Idle" => {"contexts" => SimpleCov::ContextMap.new.to_h})

      expect(union.map.contexts).to eq(["spec/a_spec.rb:1"])
    end

    context "when only some entries carry a map" do
      before do
        union.absorb_resultset("RSpec" => map_entry("spec/a_spec.rb:1", 0b1))
        union.absorb_resultset("Cucumber" => {})
      end

      it "is not complete" do
        expect(union).not_to be_complete
      end

      it "drops the union" do
        expect(without_stderr { union.map }).to be_nil
      end

      it "drops it out loud" do
        expect(capture_stderr { union.map }).to include("Dropped the per-test map", "1 of 2 merged results")
      end
    end

    it "treats a malformed map the same as an absent one" do
      union.absorb_resultset("RSpec" => {"contexts" => "junk"})

      expect(union).not_to be_complete
    end

    context "when print_errors is off" do
      before do
        union.absorb_entry(map_entry("spec/a_spec.rb:1", 0b1))
        union.absorb_entry({})
        allow(SimpleCov).to receive(:print_errors).and_return(false)
      end

      it "still drops the union" do
        expect(union.map).to be_nil
      end

      it "stays quiet about the drop" do
        expect(capture_stderr { union.map }).to be_empty
      end
    end

    context "when nothing recorded a map at all" do
      before { union.absorb_resultset("RSpec" => {}, "Cucumber" => {}) }

      it "answers no map" do
        expect(without_stderr { union.map }).to be_nil
      end

      it "stays quiet" do
        expect(capture_stderr { union.map }).to be_empty
      end
    end
  end

  describe "#collector" do
    it "absorbs each resultset handed to the merge" do
      union.collector.call("RSpec" => map_entry("spec/a_spec.rb:1", 0b1))

      expect(union).to have_attributes(entries: 1, carrying: 1)
    end
  end

  describe "#absorb_union" do
    let(:other) { described_class.new }

    context "when both unions carry a map" do
      before do
        union.absorb_entry(map_entry("spec/a_spec.rb:1", 0b1))
        other.absorb_entry(map_entry("spec/b_spec.rb:2", 0b10))

        union.absorb_union(other)
      end

      it "folds the other union's counts in" do
        expect(union).to have_attributes(entries: 2, carrying: 2)
      end

      it "folds the other union's map in" do
        expect(union.map.contexts).to contain_exactly("spec/a_spec.rb:1", "spec/b_spec.rb:2")
      end
    end

    context "when the other union carries a map for only some of its entries" do
      before do
        union.absorb_entry(map_entry("spec/a_spec.rb:1", 0b1))
        other.absorb_entry(map_entry("spec/b_spec.rb:2", 0b10))
        other.absorb_entry(map_entry("spec/c_spec.rb:3", 0b100))
        other.absorb_entry({})
      end

      it "adds the other union's totals to its own" do
        union.absorb_union(other)

        expect(union).to have_attributes(entries: 4, carrying: 3)
      end
    end

    it "goes incomplete when the absorbed union is incomplete" do
      union.absorb_entry(map_entry("spec/a_spec.rb:1", 0b1))
      other.absorb_entry({})

      union.absorb_union(other)

      expect(union).not_to be_complete
    end

    it "stays incomplete once it is, whatever the absorbed union carries" do
      union.absorb_entry({})
      other.absorb_entry(map_entry("spec/a_spec.rb:1", 0b1))

      union.absorb_union(other)

      expect(union).not_to be_complete
    end

    it "answers itself, so unions chain" do
      expect(union.absorb_union(described_class.new)).to be(union)
    end
  end
end
