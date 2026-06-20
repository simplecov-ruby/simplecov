# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::Combine::BranchesCombiner do
  describe ".combine" do
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
  end
end
