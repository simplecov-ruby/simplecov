# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::Combine::LinesCombiner do
  describe ".merge_into" do
    it "folds the source into the target, summing overlaps" do
      expect(described_class.merge_into([1, nil, 0], [2, 1, nil, 3])).to eq([3, 1, 0, 3])
    end

    it "grows the target to the longer input" do
      expect(described_class.merge_into([1, 0, nil], [1, 1, nil, 1, nil])).to eq([2, 1, nil, 1, nil])
    end

    # The relevance rules: nil + nil = nil, nil + int = int (preserving a
    # relevant-but-uncovered 0 rather than dropping the line from the
    # denominator), int + int = sum.
    it "treats a line as relevant when either side says so" do
      expect(described_class.merge_into([nil, 0, 5, nil], [nil, nil, nil, 0])).to eq([nil, 0, 5, 0])
    end

    it "returns the target untouched when there is no source" do
      target = [1, nil]
      expect(described_class.merge_into(target, nil)).to be(target)
    end

    it "duplicates the source when there is no target yet" do
      source = [1, nil]
      expect(described_class.merge_into(nil, source)).to eq(source)
      expect(described_class.merge_into(nil, source)).not_to be(source)
    end

    it "never mutates the source array" do
      source = [1, 1, nil, 1, nil]
      described_class.merge_into([1, 0, nil], source)
      expect(source).to eq([1, 1, nil, 1, nil])
    end

    # Resultsets are external input, so the hot loop coerces malformed
    # counts to a wrong answer instead of raising mid-merge.
    it "coerces malformed counts instead of raising" do
      expect(described_class.merge_into(["2", nil], [1, "3", 1.0])).to eq([3, 3, 1])
    end
  end
end
