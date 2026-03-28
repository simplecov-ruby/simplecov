# frozen_string_literal: true

require "helper"

describe SimpleCov::Combine::MethodsCombiner do
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
  end
end
