# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::Combine::LinesCombiner do
  describe ".combine" do
    it "uses coverage_a as the accumulator when it is longer" do
      a = [1, 1, nil, 1, nil]
      b = [1, 0, nil]
      expect(described_class.combine(a, b)).to eq([2, 1, nil, 1, nil])
    end

    it "uses coverage_b as the accumulator when it is longer" do
      a = [1, 0, nil]
      b = [1, 1, nil, 1, nil]
      expect(described_class.combine(a, b)).to eq([2, 1, nil, 1, nil])
    end
  end

  describe ".merge_line_coverage" do
    it "treats nil + 0 as nil (line never relevant on either side)" do
      expect(described_class.merge_line_coverage(nil, 0)).to be_nil
    end

    it "sums integer hits" do
      expect(described_class.merge_line_coverage(2, 3)).to eq(5)
    end
  end
end
