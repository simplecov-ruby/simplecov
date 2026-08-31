# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::Combine::BranchesCombiner do
  let(:static_branch_coverage) do
    {
      [:if, 9, 110, 12, 110, 34] => {
        [:then, 10, 110, 12, 110, 16] => 0,
        [:else, 11, 110, 12, 110, 34] => 0
      }
    }
  end

  let(:shifted_branch_coverage) do
    {
      [:if, 12, 110, 12, 110, 34] => {
        [:then, 13, 110, 12, 110, 16] => 2,
        [:else, 14, 110, 12, 110, 34] => 3
      }
    }
  end

  describe ".combine" do
    it "does not double-count the same branch when equivalent branch ids differ" do
      merged = described_class.combine(static_branch_coverage, shifted_branch_coverage)

      expect(merged.size).to eq(1)
      expect(merged).to eq(
        [:if, 9, 110, 12, 110, 34] => {
          [:then, 10, 110, 12, 110, 16] => 2,
          [:else, 11, 110, 12, 110, 34] => 3
        }
      )
    end

    it "does not double-count equivalent serialized branch keys from JSON resultsets" do
      serialized_static = static_branch_coverage.to_h do |condition, branches|
        [condition.inspect, branches.transform_keys(&:inspect)]
      end
      serialized_shifted = shifted_branch_coverage.to_h do |condition, branches|
        [condition.inspect, branches.transform_keys(&:inspect)]
      end

      merged = described_class.combine(serialized_static, serialized_shifted)

      expect(merged.size).to eq(1)
      expect(merged).to eq(
        "[:if, 9, 110, 12, 110, 34]" => {
          "[:then, 10, 110, 12, 110, 16]" => 2,
          "[:else, 11, 110, 12, 110, 34]" => 3
        }
      )
    end

    it "keeps the side that has data when the other is missing" do
      expect(described_class.combine(static_branch_coverage, nil)).to eq(static_branch_coverage)
      expect(described_class.combine(nil, static_branch_coverage)).to eq(static_branch_coverage)
    end

    it "answers an empty table when neither side has data" do
      expect(described_class.combine(nil, nil)).to eq({})
    end

    it "does not double-count when one side is serialized and the other is not" do
      serialized_shifted = shifted_branch_coverage.to_h do |condition, branches|
        [condition.inspect, branches.transform_keys(&:inspect)]
      end

      merged = described_class.combine(static_branch_coverage, serialized_shifted)

      expect(merged.size).to eq(1)
      expect(merged).to eq(
        [:if, 9, 110, 12, 110, 34] => {
          [:then, 10, 110, 12, 110, 16] => 2,
          [:else, 11, 110, 12, 110, 34] => 3
        }
      )
    end
  end

  describe ".absorb" do
    it "returns the target untouched when there is no coverage to fold in" do
      target = {}

      expect(described_class.absorb(target, nil)).to be(target)
      expect(target).to eq({})
    end

    it "folds into the target it was given and answers it" do
      target = {}

      expect(described_class.absorb(target, static_branch_coverage)).to be(target)
      expect(described_class.materialize(target)).to eq(static_branch_coverage)
    end

    it "sums the arms of a condition it has already absorbed" do
      target = described_class.absorb({}, shifted_branch_coverage)
      described_class.absorb(target, shifted_branch_coverage)

      expect(described_class.materialize(target)).to eq(
        [:if, 12, 110, 12, 110, 34] => {
          [:then, 13, 110, 12, 110, 16] => 4,
          [:else, 14, 110, 12, 110, 34] => 6
        }
      )
    end

    it "keeps a condition no later coverage carries" do
      other_condition = {[:if, 20, 200, 2, 200, 8] => {[:then, 21, 200, 2, 200, 4] => 5}}
      target = described_class.absorb({}, static_branch_coverage)
      described_class.absorb(target, other_condition)

      expect(described_class.materialize(target)).to eq(static_branch_coverage.merge(other_condition))
    end

    it "keeps the arm keys of the condition it saw first" do
      target = described_class.absorb({}, static_branch_coverage)
      described_class.absorb(target, shifted_branch_coverage)

      expect(described_class.materialize(target)).to eq(
        [:if, 9, 110, 12, 110, 34] => {
          [:then, 10, 110, 12, 110, 16] => 2,
          [:else, 11, 110, 12, 110, 34] => 3
        }
      )
    end
  end

  describe ".materialize" do
    it "answers an empty hash for a table nothing was absorbed into" do
      expect(described_class.materialize({})).to eq({})
    end
  end

  describe ".new_condition" do
    it "pairs the condition with an empty arm table" do
      expect(described_class.new_condition([:if, 9, 110, 12, 110, 34]))
        .to eq([[:if, 9, 110, 12, 110, 34], {}])
    end

    it "gives every condition an arm table of its own" do
      expect(described_class.new_condition(:a).fetch(1)).not_to be(described_class.new_condition(:b).fetch(1))
    end
  end

  describe ".tuple_identity" do
    it "is the type and the source span, ignoring the branch id" do
      expect(described_class.tuple_identity([:then, 4, 8, 6, 9, 12])).to eq([:then, 8, 6, 9, 12])
    end

    it "reads a serialized tuple to the same identity" do
      expect(described_class.tuple_identity("[:then, 5, 8, 6, 9, 12]")).to eq([:then, 8, 6, 9, 12])
    end

    it "is frozen" do
      expect(described_class.tuple_identity([:then, 4, 8, 6, 9, 12])).to be_frozen
    end
  end

  describe ".identities" do
    it "is memoized, so a fold interns each condition once" do
      identities = described_class.identities

      expect(described_class.identities).to be(identities)
    end

    it "gives two tuples of the same span one id, and different spans different ids" do
      identities = described_class.identities

      expect(identities[[:if, 3, 8, 6, 8, 36]]).to eq(identities[[:if, 4, 8, 6, 8, 36]])
      expect(identities[[:if, 3, 8, 6, 8, 36]]).not_to eq(identities[[:if, 3, 9, 6, 8, 36]])
    end
  end
end
