# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::Combine::ResultsCombiner do
  describe "with two faked coverage resultsets" do
    let(:first_resultset) do
      {
        source_fixture("sample.rb") => {
          "lines" => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil],
          "branches" => {[:if, 3, 8, 6, 8, 36] => {[:then, 4, 8, 6, 8, 12] => 47, [:else, 5, 8, 6, 8, 36] => 24}}
        },
        source_fixture("app/models/user.rb") => {
          "lines" => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil],
          "branches" => {[:if, 3, 8, 6, 8, 36] => {[:then, 4, 8, 6, 8, 12] => 47, [:else, 5, 8, 6, 8, 36] => 24}}
        },
        source_fixture("app/controllers/sample_controller.rb") => {"lines" => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil]},
        source_fixture("resultset1.rb") => {"lines" => [1, 1, 1, 1]},
        source_fixture("parallel_tests.rb") => {"lines" => [nil, 0, nil, 0]},
        source_fixture("conditionally_loaded_1.rb") => {"lines" => [nil, 0, 1]},
        source_fixture("three.rb") => {"lines" => [nil, 1, 1]}
      }
    end

    let(:second_resultset) do
      {
        source_fixture("sample.rb") => {"lines" => [1, nil, 1, 1, nil, nil, 1, 1, nil, nil]},
        source_fixture("app/models/user.rb") => {
          "lines" => [nil, 1, 5, 1, nil, nil, 1, 0, nil, nil],
          "branches" => {[:if, 3, 8, 6, 8, 36] => {[:then, 4, 8, 6, 8, 12] => 1, [:else, 5, 8, 6, 8, 36] => 2}}
        },
        source_fixture("app/controllers/sample_controller.rb") => {
          "lines" => [nil, 3, 1, nil, nil, nil, 1, 0, nil, nil]
        },
        source_fixture("resultset2.rb") => {"lines" => [nil, 1, 1, nil]},
        source_fixture("parallel_tests.rb") => {"lines" => [nil, nil, 0, 0]},
        source_fixture("conditionally_loaded_2.rb") => {"lines" => [nil, 0, 1]},
        source_fixture("three.rb") => {"lines" => [nil, 1, 4]}
      }
    end

    let(:third_resultset) do
      {source_fixture("three.rb") => {"lines" => [nil, 1, 2]}}
    end

    after do
      SimpleCov.clear_coverage_criteria
    end

    before do
      SimpleCov.enable_coverage :branch
    end

    context "when a merge" do
      subject(:combined) do
        described_class.combine(first_resultset, second_resultset, third_resultset)
      end

      it "has proper line results for sample.rb" do
        expect(combined[source_fixture("sample.rb")]["lines"]).to eq([1, 1, 2, 2, nil, nil, 2, 2, nil, nil])
      end

      it "has proper branch results for sample.rb", if: SimpleCov.branch_coverage_supported? do
        branches = combined[source_fixture("sample.rb")]["branches"]

        expect(branches[[:if, 3, 8, 6, 8, 36]][[:then, 4, 8, 6, 8, 12]]).to eq(47)
      end

      it "has proper results for parallel_tests.rb" do
        expect(combined[source_fixture("parallel_tests.rb")]["lines"]).to eq([nil, 0, 0, 0])
      end
    end
  end

  describe "with method coverage", if: SimpleCov.method_coverage_supported? do
    before { SimpleCov.enable_coverage :method }
    after { SimpleCov.clear_coverage_criteria }

    let(:resultset_a) do
      {
        source_fixture("sample.rb") => {
          "lines" => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil],
          "methods" => {["FakedProject", :foo, 4, 2, 6, 5] => 1, ["FakedProject", :bar, 1, 2, 3, 4] => 0}
        }
      }
    end
    let(:resultset_b) do
      {
        source_fixture("sample.rb") => {
          "lines" => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil],
          "methods" => {["FakedProject", :foo, 4, 2, 6, 5] => 5, ["FakedProject", :baz, 7, 2, 9, 4] => 3}
        }
      }
    end
    let(:merged_methods) do
      described_class.combine(resultset_a, resultset_b)[source_fixture("sample.rb")]["methods"]
    end

    it "sums the calls of a method both sides recorded" do
      expect(merged_methods[["FakedProject", :foo, 4, 2, 6, 5]]).to eq(6)
    end

    it "keeps a method only the first side recorded" do
      expect(merged_methods[["FakedProject", :bar, 1, 2, 3, 4]]).to eq(0)
    end

    it "keeps a method only the second side recorded" do
      expect(merged_methods[["FakedProject", :baz, 7, 2, 9, 4]]).to eq(3)
    end
  end

  describe "with nothing to merge" do
    it "combines no results at all into an empty coverage" do
      expect(described_class.combine).to eq({})
    end

    it "combines results that carried no coverage into an empty coverage" do
      expect(described_class.combine(nil, nil)).to eq({})
    end

    it "keeps the coverage of the one result that carried any" do
      coverage = {source_fixture("sample.rb") => {"lines" => [nil, 1, 3]}}

      expect(described_class.combine(nil, coverage)).to eq(coverage)
    end
  end

  describe "merging frozen resultsets" do
    let(:first_resultset) do
      {
        source_fixture("sample.rb").freeze => {"lines" => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil]},
        source_fixture("app/models/user.rb").freeze => {"lines" => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil]}
      }
    end
    let(:second_resultset) do
      {source_fixture("sample.rb").freeze => {"lines" => [1, nil, 1, 1, nil, nil, 1, 1, nil, nil]}}
    end
    let(:merged_result) { described_class.combine(first_resultset, second_resultset) }

    it "keeps every file either side carried" do
      expect(merged_result.keys).to eq(first_resultset.keys)
    end

    it "answers unfrozen coverage" do
      expect(merged_result.values.map(&:frozen?)).to eq([false, false])
    end

    it "sums the lines of the file both sides carried" do
      expect(merged_result[source_fixture("sample.rb")]["lines"]).to eq([1, 1, 2, 2, nil, nil, 2, 2, nil, nil])
    end

    it "keeps the lines of the file only one side carried" do
      expect(merged_result[source_fixture("app/models/user.rb")]["lines"])
        .to eq([nil, 1, 1, 1, nil, nil, 1, 0, nil, nil])
    end
  end
end
