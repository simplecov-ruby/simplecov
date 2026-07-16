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
        source_fixture("conditionally_loaded_1.rb") => {"lines" => [nil, 0, 1]},  # loaded only in the first resultset
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
        source_fixture("conditionally_loaded_2.rb") => {"lines" => [nil, 0, 1]},  # loaded only in the second resultset
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

      it "has proper results for sample.rb" do
        expect(combined[source_fixture("sample.rb")]["lines"]).to eq([1, 1, 2, 2, nil, nil, 2, 2, nil, nil])

        if SimpleCov.branch_coverage_supported?
          branches = combined[source_fixture("sample.rb")]["branches"]
          expect(branches[[:if, 3, 8, 6, 8, 36]][[:then, 4, 8, 6, 8, 12]]).to eq(47)
        end
      end

      it "has proper results for user.rb" do
        expect(combined[source_fixture("app/models/user.rb")]["lines"]).to eq([nil, 2, 6, 2, nil, nil, 2, 0, nil, nil])

        if SimpleCov.branch_coverage_supported?
          branches = combined[source_fixture("app/models/user.rb")]["branches"]
          expect(branches[[:if, 3, 8, 6, 8, 36]][[:then, 4, 8, 6, 8, 12]]).to eq(48)
          expect(branches[[:if, 3, 8, 6, 8, 36]][[:else, 5, 8, 6, 8, 36]]).to eq(26)
        end
      end

      it "has proper results for sample_controller.rb" do
        lines = combined[source_fixture("app/controllers/sample_controller.rb")]["lines"]
        expect(lines).to eq([nil, 4, 2, 1, nil, nil, 2, 0, nil, nil])
      end

      it "has proper results for resultset1.rb" do
        expect(combined[source_fixture("resultset1.rb")]["lines"]).to eq([1, 1, 1, 1])
      end

      it "has proper results for resultset2.rb" do
        expect(combined[source_fixture("resultset2.rb")]["lines"]).to eq([nil, 1, 1, nil])
      end

      it "has proper results for parallel_tests.rb" do
        # First resultset reports [nil, 0, nil, 0]; second reports
        # [nil, nil, 0, 0]. A line is treated as relevant when either
        # side considered it relevant, so positions 1 and 2 stay at
        # 0 rather than collapsing to nil.
        expect(combined[source_fixture("parallel_tests.rb")]["lines"]).to eq([nil, 0, 0, 0])
      end

      it "has proper results for conditionally_loaded_1.rb" do
        expect(combined[source_fixture("conditionally_loaded_1.rb")]["lines"]).to eq([nil, 0, 1])
      end

      it "has proper results for conditionally_loaded_2.rb" do
        expect(combined[source_fixture("conditionally_loaded_2.rb")]["lines"]).to eq([nil, 0, 1])
      end

      it "has proper results for three.rb" do
        expect(combined[source_fixture("three.rb")]["lines"]).to eq([nil, 3, 7])
      end

      it "always returns a Hash object for branches", if: SimpleCov.branch_coverage_supported? do
        expect(combined[source_fixture("three.rb")]["branches"]).to eq({})
      end
    end
  end

  describe "with method coverage", if: SimpleCov.method_coverage_supported? do
    before { SimpleCov.enable_coverage :method }
    after { SimpleCov.clear_coverage_criteria }

    it "merges method coverage data" do
      resultset_a = {
        source_fixture("sample.rb") => {
          "lines" => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil],
          "methods" => {["FakedProject", :foo, 4, 2, 6, 5] => 1, ["FakedProject", :bar, 1, 2, 3, 4] => 0}
        }
      }
      resultset_b = {
        source_fixture("sample.rb") => {
          "lines" => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil],
          "methods" => {["FakedProject", :foo, 4, 2, 6, 5] => 5, ["FakedProject", :baz, 7, 2, 9, 4] => 3}
        }
      }

      merged = described_class.combine(resultset_a, resultset_b)
      methods = merged[source_fixture("sample.rb")]["methods"]

      expect(methods[["FakedProject", :foo, 4, 2, 6, 5]]).to eq(6)
      expect(methods[["FakedProject", :bar, 1, 2, 3, 4]]).to eq(0)
      expect(methods[["FakedProject", :baz, 7, 2, 9, 4]]).to eq(3)
    end
  end

  it "merges frozen resultsets" do
    first_resultset = {
      source_fixture("sample.rb").freeze => {"lines" => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil]},
      source_fixture("app/models/user.rb").freeze => {"lines" => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil]}
    }

    second_resultset = {
      source_fixture("sample.rb").freeze => {"lines" => [1, nil, 1, 1, nil, nil, 1, 1, nil, nil]}
    }

    merged_result = described_class.combine(first_resultset, second_resultset)
    expect(merged_result.keys).to eq(first_resultset.keys)
    expect(merged_result.values.map(&:frozen?)).to eq([false, false])

    expect(merged_result[source_fixture("sample.rb")]["lines"]).to eq([1, 1, 2, 2, nil, nil, 2, 2, nil, nil])
    expect(merged_result[source_fixture("app/models/user.rb")]["lines"]).to eq([nil, 1, 1, 1, nil, nil, 1, 0, nil, nil])
  end

  # End-to-end analogue of the #1233 collate scenario: one worker executed
  # the file (real branches), another only tracked it (simulated branches
  # whose tuple has drifted). The merge must keep the executed worker's
  # tuple and drop the simulated one rather than carry a phantom miss.
  describe "reconciling a simulated file against an executed one",
           if: SimpleCov.branch_coverage_supported? do
    around do |example|
      SimpleCov.enable_coverage(:branch)
      example.run
      SimpleCov.clear_coverage_criteria
    end

    it "keeps only the executed worker's branch tuple" do
      executed_worker = {
        source_fixture("sample.rb") => {
          "lines" => [nil, 1, 1, 0, nil],
          "branches" => {[:if, 0, 2, 2, 4, 10] => {[:then, 1, 3, 4, 3, 10] => 1, [:else, 2, 4, 4, 4, 10] => 0}}
        }
      }
      tracking_worker = {
        source_fixture("sample.rb") => {
          "lines" => [nil, 0, 0, 0, nil],
          "branches" => {[:if, 0, 2, 2, 4, 12] => {[:then, 1, 3, 4, 3, 10] => 0, [:else, 2, 4, 4, 4, 12] => 0}}
        }
      }

      combined = described_class.combine(executed_worker, tracking_worker)

      expect(combined[source_fixture("sample.rb")]["branches"].keys).to eq([[:if, 0, 2, 2, 4, 10]])
    end
  end
end
