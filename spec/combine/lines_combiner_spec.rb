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

    it "leaves the target's tail alone when the source is the shorter side" do
      expect(described_class.merge_into([3, 7, 5], [4, 2])).to eq([7, 9, 5])
    end

    it "sums the whole overlap when the two sides are the same length" do
      expect(described_class.merge_into([3, 7], [4, 2])).to eq([7, 9])
    end

    it "returns the target itself rather than a copy of it" do
      target = [3, 7]

      expect(described_class.merge_into(target, [4, 2])).to be(target)
      expect(target).to eq([7, 9])
    end

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

    it "coerces malformed counts instead of raising" do
      expect(described_class.merge_into(["2", nil], [1, "3", 1.0])).to eq([3, 3, 1])
    end

    it "contributes nothing from a source that is not a lines array" do
      expect(described_class.merge_into([3, 7], {"a" => 1})).to eq([3, 7])
    end
  end

  describe ".sum_into" do
    it "sums each position and answers the target it folded into" do
      target = [3, nil, 7]

      expect(described_class.sum_into(target, [5, 4, 2], 3)).to be(target)
      expect(target).to eq([8, 4, 9])
    end

    it "reads a count that carries trailing text as far as it is a number" do
      expect(described_class.sum_into([3], ["5 hits"], 1)).to eq([8])
    end

    it "stops at the size it was given" do
      expect(described_class.sum_into([3, 7], [5, 4], 1)).to eq([8, 7])
    end

    it "leaves a position the source says nothing about alone" do
      expect(described_class.sum_into([3, 7], [nil, 4], 2)).to eq([3, 11])
    end

    it "makes a position only the source considers relevant relevant" do
      expect(described_class.sum_into([nil, nil], [0, 4], 2)).to eq([0, 4])
    end

    it "coerces malformed counts on both sides instead of raising" do
      expect(described_class.sum_into([nil, "6"], ["3", 4.7], 2)).to eq([3, 10])
    end

    it "leaves a position neither side considers relevant alone" do
      expect(described_class.sum_into([nil, 3], [nil, 4], 2)).to eq([nil, 7])
    end

    it "contributes nothing from a position the source does not reach" do
      expect(described_class.sum_into([3, 7], [5], 2)).to eq([8, 7])
    end

    it "grows a target shorter than the size it was given" do
      expect(described_class.sum_into([3], [5, 4], 2)).to eq([8, 4])
    end
  end
end
