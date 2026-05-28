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
