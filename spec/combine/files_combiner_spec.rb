# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::Combine::FilesCombiner do
  # A real, executed file: some line ran, and its branch tuples come from
  # Coverage, so they sit at the exact positions Coverage reports.
  let(:executed) do
    {
      "lines" => [nil, 1, 1, 0, nil],
      "branches" => {
        [:if, 0, 2, 2, 4, 10] => {[:then, 1, 3, 4, 3, 10] => 1, [:else, 2, 4, 4, 4, 10] => 0}
      }
    }
  end

  # A simulated (tracked-but-never-loaded) file: every line is nil / 0, and
  # its branch tuples are synthesized. Here the `if` condition's end column
  # has drifted (…4, 12] vs …4, 10]), the exact failure mode of #1233.
  let(:simulated_drifted) do
    {
      "lines" => [nil, 0, 0, 0, nil],
      "branches" => {
        [:if, 0, 2, 2, 4, 12] => {[:then, 1, 3, 4, 3, 10] => 0, [:else, 2, 4, 4, 4, 12] => 0}
      }
    }
  end

  around do |example|
    SimpleCov.enable_coverage(:branch)
    example.run
    SimpleCov.clear_coverage_criteria
  end

  describe ".combine", if: SimpleCov.branch_coverage_supported? do
    it "drops a simulated file's branches when the other side was executed" do
      combined = described_class.combine(executed, simulated_drifted)

      # Only the executed side's real tuple survives — the drifted one would
      # otherwise be a phantom, permanently-missed branch after merge.
      expect(combined["branches"].keys).to eq([[:if, 0, 2, 2, 4, 10]])
    end

    it "is order-independent (simulated first)" do
      combined = described_class.combine(simulated_drifted, executed)

      expect(combined["branches"].keys).to eq([[:if, 0, 2, 2, 4, 10]])
    end

    it "still merges the lines from the simulated side" do
      combined = described_class.combine(executed, simulated_drifted)

      # Line shape is authoritative on both sides, so lines combine as usual
      # (the simulated side contributes its zeros / relevance).
      expect(combined["lines"]).to eq([nil, 1, 1, 0, nil])
    end

    it "keeps both branch sets when neither side was executed" do
      # Two simulated copies of a never-loaded file: no real data exists, so
      # its branches still count toward the denominator (#1059). If their
      # tuples happen to disagree, both survive — denominator inflation, the
      # acceptable fallback, rather than a false miss on a covered file.
      other = {
        "lines" => [nil, 0, 0, 0, nil],
        "branches" => {[:if, 0, 2, 2, 4, 20] => {[:then, 1, 3, 4, 3, 10] => 0, [:else, 2, 4, 4, 4, 20] => 0}}
      }

      combined = described_class.combine(simulated_drifted, other)

      expect(combined["branches"].keys).to contain_exactly([:if, 0, 2, 2, 4, 12], [:if, 0, 2, 2, 4, 20])
    end

    it "unions two executed runs of the same file normally" do
      other_run = {
        "lines" => [nil, 1, 1, 1, nil],
        "branches" => {
          [:if, 0, 2, 2, 4, 10] => {[:then, 1, 3, 4, 3, 10] => 4, [:else, 2, 4, 4, 4, 10] => 5}
        }
      }

      combined = described_class.combine(executed, other_run)
      arms = combined["branches"][[:if, 0, 2, 2, 4, 10]]

      expect(arms[[:then, 1, 3, 4, 3, 10]]).to eq(5)
      expect(arms[[:else, 2, 4, 4, 4, 10]]).to eq(5)
    end
  end

  describe ".combine method coverage", if: SimpleCov.method_coverage_supported? do
    around do |example|
      SimpleCov.enable_coverage(:method)
      example.run
      SimpleCov.clear_coverage_criteria
    end

    it "drops a simulated file's methods when the other side was executed" do
      executed_methods = {
        "lines" => [nil, 1, 1],
        "methods" => {["Foo", :bar, 2, 2, 3, 5] => 1}
      }
      simulated_methods = {
        "lines" => [nil, 0, 0],
        "methods" => {["Foo", :bar, 2, 2, 3, 7] => 0} # drifted end column
      }

      combined = described_class.combine(executed_methods, simulated_methods)

      expect(combined["methods"].keys).to eq([["Foo", :bar, 2, 2, 3, 5]])
    end
  end
end
