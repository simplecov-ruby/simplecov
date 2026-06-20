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

    let(:runtime_branch_coverage) do
      {
        [:unless, 9, 110, 12, 110, 34] => {
          [:else, 10, 110, 12, 110, 34] => 15,
          [:then, 11, 110, 12, 110, 16] => 0
        }
      }
    end

    it "does not double-count the same branch when static and runtime condition types differ" do
      merged = described_class.combine(static_branch_coverage, runtime_branch_coverage)

      expect(merged.size).to eq(1)
      expect(merged).to eq(
        [:unless, 9, 110, 12, 110, 34] => {
          [:then, 11, 110, 12, 110, 16] => 0,
          [:else, 10, 110, 12, 110, 34] => 15
        }
      )
    end
  end
end
