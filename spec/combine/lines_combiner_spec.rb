# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::Combine::LinesCombiner do
  describe ".combine" do
    it "returns a fresh array sized to the longer input when coverage_a is longer" do
      a = [1, 1, nil, 1, nil]
      b = [1, 0, nil]
      expect(described_class.combine(a, b)).to eq([2, 1, nil, 1, nil])
    end

    it "returns a fresh array sized to the longer input when coverage_b is longer" do
      a = [1, 0, nil]
      b = [1, 1, nil, 1, nil]
      expect(described_class.combine(a, b)).to eq([2, 1, nil, 1, nil])
    end

    it "doesn't mutate either input array" do
      a = [1, 1, nil, 1, nil]
      b = [1, 0, nil]
      described_class.combine(a, b)
      expect(a).to eq([1, 1, nil, 1, nil])
      expect(b).to eq([1, 0, nil])
    end
  end

  describe ".merge_into" do
    it "folds the source into the target, summing overlaps" do
      expect(described_class.merge_into([1, nil, 0], [2, 1, nil, 3])).to eq([3, 1, 0, 3])
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

    # Resultsets are external input, so the hot loop coerces malformed
    # counts the same way `merge_line_coverage`'s to_i path does — the
    # two entry points must answer alike.
    it "coerces malformed counts like merge_line_coverage does" do
      expect(described_class.merge_into(["2", nil], [1, "3", 1.0])).to eq([3, 3, 1])
      expect(described_class.merge_line_coverage("2", 1)).to eq(3)
    end
  end

  describe ".merge_line_coverage" do
    it "returns nil only when both sides are nil" do
      expect(described_class.merge_line_coverage(nil, nil)).to be_nil
    end

    it "preserves a relevant-but-uncovered 0 when the other side is nil" do
      expect(described_class.merge_line_coverage(0, nil)).to eq(0)
      expect(described_class.merge_line_coverage(nil, 0)).to eq(0)
    end

    it "sums integer hits" do
      expect(described_class.merge_line_coverage(2, 3)).to eq(5)
    end

    it "treats nil as 0 when summing with a non-nil int" do
      expect(described_class.merge_line_coverage(5, nil)).to eq(5)
      expect(described_class.merge_line_coverage(nil, 5)).to eq(5)
    end
  end
end
