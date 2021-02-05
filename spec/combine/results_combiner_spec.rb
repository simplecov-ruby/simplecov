# frozen_string_literal: true

require "helper"

describe SimpleCov::Combine::ResultsCombiner do
  describe "with two faked coverage resultsets" do
    let(:resultset1) do
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

    let(:resultset2) do
      {
        source_fixture("sample.rb") => {"lines" => [1, nil, 1, 1, nil, nil, 1, 1, nil, nil]},
        source_fixture("app/models/user.rb") => {
          "lines" => [nil, 1, 5, 1, nil, nil, 1, 0, nil, nil],
          "branches" => {[:if, 3, 8, 6, 8, 36] => {[:then, 4, 8, 6, 8, 12] => 1, [:else, 5, 8, 6, 8, 36] => 2}}
        },
        source_fixture("app/controllers/sample_controller.rb") => {"lines" => [nil, 3, 1, nil, nil, nil, 1, 0, nil, nil]},
        source_fixture("resultset2.rb") => {"lines" => [nil, 1, 1, nil]},
        source_fixture("parallel_tests.rb") => {"lines" => [nil, nil, 0, 0]},
        source_fixture("conditionally_loaded_2.rb") => {"lines" => [nil, 0, 1]},  # loaded only in the second resultset
        source_fixture("three.rb") => {"lines" => [nil, 1, 4]}
      }
    end

    let(:resultset3) do
      {source_fixture("three.rb") => {"lines" => [nil, 1, 2]}}
    end

    after do
      SimpleCov.clear_coverage_criteria
    end

    before do
      SimpleCov.enable_coverage :branch
    end

    context "a merge" do
      subject do
        SimpleCov::Combine::ResultsCombiner.combine(resultset1, resultset2, resultset3)
      end

      it "has proper results for sample.rb" do
        expect(subject[source_fixture("sample.rb")]["lines"]).to eq([1, 1, 2, 2, nil, nil, 2, 2, nil, nil])

        # gotta configure max line so it doesn't get ridiculous
        # rubocop:disable Style/IfUnlessModifier
        if SimpleCov.branch_coverage_supported?
          expect(subject[source_fixture("sample.rb")]["branches"][[:if, 3, 8, 6, 8, 36]][[:then, 4, 8, 6, 8, 12]]).to eq(47)
        end
        # rubocop:enable Style/IfUnlessModifier
      end

      it "has proper results for user.rb" do
        expect(subject[source_fixture("app/models/user.rb")]["lines"]).to eq([nil, 2, 6, 2, nil, nil, 2, 0, nil, nil])

        if SimpleCov.branch_coverage_supported?
          expect(subject[source_fixture("app/models/user.rb")]["branches"][[:if, 3, 8, 6, 8, 36]][[:then, 4, 8, 6, 8, 12]]).to eq(48)
          expect(subject[source_fixture("app/models/user.rb")]["branches"][[:if, 3, 8, 6, 8, 36]][[:else, 5, 8, 6, 8, 36]]).to eq(26)
        end
      end

      it "has proper results for sample_controller.rb" do
        expect(subject[source_fixture("app/controllers/sample_controller.rb")]["lines"]).to eq([nil, 4, 2, 1, nil, nil, 2, 0, nil, nil])
      end

      it "has proper results for resultset1.rb" do
        expect(subject[source_fixture("resultset1.rb")]["lines"]).to eq([1, 1, 1, 1])
      end

      it "has proper results for resultset2.rb" do
        expect(subject[source_fixture("resultset2.rb")]["lines"]).to eq([nil, 1, 1, nil])
      end

      it "has proper results for parallel_tests.rb" do
        expect(subject[source_fixture("parallel_tests.rb")]["lines"]).to eq([nil, nil, nil, 0])
      end

      it "has proper results for conditionally_loaded_1.rb" do
        expect(subject[source_fixture("conditionally_loaded_1.rb")]["lines"]).to eq([nil, 0, 1])
      end

      it "has proper results for conditionally_loaded_2.rb" do
        expect(subject[source_fixture("conditionally_loaded_2.rb")]["lines"]).to eq([nil, 0, 1])
      end

      it "has proper results for three.rb" do
        expect(subject[source_fixture("three.rb")]["lines"]).to eq([nil, 3, 7])
      end

      it "always returns a Hash object for branches", if: SimpleCov.branch_coverage_supported? do
        expect(subject[source_fixture("three.rb")]["branches"]).to eq({})
      end
    end
  end

  it "merges frozen resultsets" do
    resultset1 = {
      source_fixture("sample.rb").freeze => {"lines" => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil]},
      source_fixture("app/models/user.rb").freeze => {"lines" => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil]}
    }

    resultset2 = {
      source_fixture("sample.rb").freeze => {"lines" => [1, nil, 1, 1, nil, nil, 1, 1, nil, nil]}
    }

    merged_result = SimpleCov::Combine::ResultsCombiner.combine(resultset1, resultset2)
    expect(merged_result.keys).to eq(resultset1.keys)
    expect(merged_result.values.map(&:frozen?)).to eq([false, false])

    expect(merged_result[source_fixture("sample.rb")]["lines"]).to eq([1, 1, 2, 2, nil, nil, 2, 2, nil, nil])
    expect(merged_result[source_fixture("app/models/user.rb")]["lines"]).to eq([nil, 1, 1, 1, nil, nil, 1, 0, nil, nil])
  end
end
