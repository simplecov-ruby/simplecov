# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::Combine::MethodsCombiner do
  describe ".combine" do
    it "sums coverage for matching method keys" do
      coverage_a = {
        '["A", :method1, 2, 2, 5, 5]' => 3,
        '["A", :method2, 9, 2, 11, 5]' => 0
      }
      coverage_b = {
        '["A", :method1, 2, 2, 5, 5]' => 2,
        '["A", :method2, 9, 2, 11, 5]' => 1
      }

      result = described_class.combine(coverage_a, coverage_b)

      expect(result).to eq(
        '["A", :method1, 2, 2, 5, 5]' => 5,
        '["A", :method2, 9, 2, 11, 5]' => 1
      )
    end

    it "preserves methods unique to one side" do
      coverage_a = {'["A", :method1, 2, 2, 5, 5]' => 1}
      coverage_b = {'["B", :method2, 9, 2, 11, 5]' => 2}

      result = described_class.combine(coverage_a, coverage_b)

      expect(result).to eq(
        '["A", :method1, 2, 2, 5, 5]' => 1,
        '["B", :method2, 9, 2, 11, 5]' => 2
      )
    end

    it "works with real array keys (not yet JSON-stringified)" do
      coverage_a = {["A", :method1, 2, 2, 5, 5] => 1}
      coverage_b = {["A", :method1, 2, 2, 5, 5] => 4}

      result = described_class.combine(coverage_a, coverage_b)

      expect(result).to eq(["A", :method1, 2, 2, 5, 5] => 5)
    end

    it "sums an array key with its JSON-stringified form" do
      coverage_a = {["A", :method1, 2, 2, 5, 5] => 1}
      coverage_b = {'["A", :method1, 2, 2, 5, 5]' => 4}

      result = described_class.combine(coverage_a, coverage_b)

      expect(result).to eq(["A", :method1, 2, 2, 5, 5] => 5)
    end

    it "matches methods on source identity, ignoring the receiver class" do
      coverage_a = {'["#<Class:0x0>", :inspect, 3, 39, 3, 51]' => 2}
      coverage_b = {'["SomeNamedClass", :inspect, 3, 39, 3, 51]' => 0}

      result = described_class.combine(coverage_a, coverage_b)

      expect(result).to eq('["#<Class:0x0>", :inspect, 3, 39, 3, 51]' => 2)
    end

    it "keeps same-named methods at different locations separate" do
      coverage_a = {'["A", :call, 2, 2, 4, 5]' => 1}
      coverage_b = {'["B", :call, 8, 2, 10, 5]' => 3}

      result = described_class.combine(coverage_a, coverage_b)

      expect(result.values).to contain_exactly(1, 3)
    end

    it "matches different generated names at the same location" do
      coverage_a = {'["#<Builder:0x0>", :echo, 38, 26, 41, 11]' => 1}
      coverage_b = {'["#<Builder:0x0>", :bind, 38, 26, 41, 11]' => 0}

      result = described_class.combine(coverage_a, coverage_b)

      expect(result).to eq('["#<Builder:0x0>", :echo, 38, 26, 41, 11]' => 1)
    end

    it "keeps the side that has data when the other is missing" do
      coverage = {'["A", :method1, 2, 2, 5, 5]' => 3}

      expect(described_class.combine(coverage, nil)).to eq(coverage)
      expect(described_class.combine(nil, coverage)).to eq(coverage)
    end

    it "answers an empty table when neither side has data" do
      expect(described_class.combine(nil, nil)).to eq({})
    end

    it "sums duplicated identities arriving within one side" do
      coverage_a = {
        '["ClassA", :method_added, 18, 55, 22, 9]' => 6,
        '["ModuleB", :method_added, 18, 55, 22, 9]' => 0
      }

      result = described_class.combine(coverage_a, {})

      expect(result).to eq('["ClassA", :method_added, 18, 55, 22, 9]' => 6)
    end
  end

  describe ".absorb" do
    let(:key) { ["A", :method1, 2, 2, 5, 5] }

    it "leaves a nil target nil while no coverage carries methods" do
      expect(described_class.absorb(nil, nil)).to be_nil
    end

    it "returns an existing target untouched when there is no coverage" do
      target = {}

      expect(described_class.absorb(target, nil)).to be(target)
      expect(target).to eq({})
    end

    it "creates the table on the first coverage that carries methods" do
      absorbed = described_class.absorb(nil, key => 3)

      expect(described_class.materialize(absorbed)).to eq(key => 3)
    end

    it "folds into the table it was given and answers it" do
      target = described_class.absorb(nil, key => 3)

      expect(described_class.absorb(target, key => 4)).to be(target)
      expect(described_class.materialize(target)).to eq(key => 7)
    end

    it "keeps a method no later coverage carries" do
      other = ["B", :method2, 9, 2, 11, 5]
      target = described_class.absorb(nil, key => 3)
      described_class.absorb(target, other => 4)

      expect(described_class.materialize(target)).to eq(key => 3, other => 4)
    end
  end

  describe ".materialize" do
    it "answers an empty hash for a table nothing was absorbed into" do
      expect(described_class.materialize({})).to eq({})
    end
  end

  describe ".source_identity" do
    it "is the location, ignoring the class and the method name" do
      expect(described_class.source_identity(["A", :method1, 2, 3, 4, 5])).to eq([2, 3, 4, 5])
    end

    it "reads a serialized key to the same identity" do
      expect(described_class.source_identity('["B", :method2, 2, 3, 4, 5]')).to eq([2, 3, 4, 5])
    end

    it "is frozen" do
      expect(described_class.source_identity(["A", :method1, 2, 3, 4, 5])).to be_frozen
    end
  end

  describe ".identities" do
    it "is memoized, so a fold interns each method once" do
      identities = described_class.identities

      expect(described_class.identities).to be(identities)
    end

    it "gives two keys of the same location one id, and different locations different ids" do
      identities = described_class.identities

      expect(identities[["A", :method1, 2, 3, 4, 5]]).to eq(identities[["B", :method2, 2, 3, 4, 5]])
      expect(identities[["A", :method1, 2, 3, 4, 5]]).not_to eq(identities[["A", :method1, 9, 3, 4, 5]])
    end
  end
end
