# frozen_string_literal: true

require "helper"
require "support/coverage_fixtures"

RSpec.describe SimpleCov::FileList do
  subject(:file_list) do
    original_result = {
      source_fixture("sample.rb") => {
        "lines" => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil],
        "branches" => {}
      },
      source_fixture("app/models/user.rb") => {
        "lines" => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil],
        "branches" => {}
      },
      source_fixture("app/controllers/sample_controller.rb") => {
        "lines" => [nil, 2, 2, 0, nil, nil, 0, nil, nil, nil],
        "branches" => {}
      }
    }
    SimpleCov::Result.new(original_result).files
  end

  it "has 11 covered lines" do
    expect(file_list.covered_lines).to eq(11)
  end

  it "has 3 missed lines" do
    expect(file_list.missed_lines).to eq(3)
  end

  it "has 17 never lines" do
    expect(file_list.never_lines).to eq(17)
  end

  it "has 14 lines of code" do
    expect(file_list.lines_of_code).to eq(14)
  end

  it "has 5 skipped lines" do
    expect(file_list.skipped_lines).to eq(5)
  end

  it "has the correct covered percent" do
    expect(file_list.covered_percent).to eq(78.57142857142857)
  end

  it "has the correct covered percentages" do
    expect(file_list.covered_percentages).to eq([50.0, 80.0, 100.0])
  end

  it "has the correct least covered file" do
    expect(file_list.least_covered_file).to match(/sample_controller.rb/)
  end

  it "has the correct covered strength" do
    expect(file_list.covered_strength).to eq(0.9285714285714286)
  end

  context "without branch or method coverage enabled" do
    let(:line_only_file_list) do
      original_result = {source_fixture("sample.rb") => CoverageFixtures::SAMPLE_RB}
      SimpleCov::Result.new(original_result).files
    end

    it "returns nil from total_branches/covered_branches/missed_branches/branch_covered_percent" do
      expect(line_only_file_list.total_branches).to be_nil
      expect(line_only_file_list.covered_branches).to be_nil
      expect(line_only_file_list.missed_branches).to be_nil
      expect(line_only_file_list.branch_covered_percent).to be_nil
    end

    it "returns nil from total_methods/covered_methods/missed_methods/method_covered_percent" do
      expect(line_only_file_list.total_methods).to be_nil
      expect(line_only_file_list.covered_methods).to be_nil
      expect(line_only_file_list.missed_methods).to be_nil
      expect(line_only_file_list.method_covered_percent).to be_nil
    end
  end

  context "when the FileList is empty" do
    let(:empty_file_list) { described_class.new([]) }

    it "returns 0.0 for never_lines and skipped_lines" do
      expect(empty_file_list.never_lines).to eq(0.0)
      expect(empty_file_list.skipped_lines).to eq(0.0)
    end
  end

  context "with branch and method coverage criteria enabled", if: SimpleCov.branch_coverage_supported? do
    around do |example|
      SimpleCov.enable_coverage :branch
      SimpleCov.enable_coverage :method
      example.run
      SimpleCov.clear_coverage_criteria
    end

    let(:branch_method_file_list) do
      original_result = {
        source_fixture("branches.rb") => CoverageFixtures::BRANCHES_RB
      }
      SimpleCov::Result.new(original_result).files
    end

    it "delegates total_branches/covered_branches/missed_branches/branch_covered_percent" do
      expect(branch_method_file_list.total_branches).to eq(6)
      expect(branch_method_file_list.covered_branches).to eq(3)
      expect(branch_method_file_list.missed_branches).to eq(3)
      expect(branch_method_file_list.branch_covered_percent).to eq(50.0)
    end

    it "delegates total_methods/covered_methods/missed_methods/method_covered_percent" do
      expect(branch_method_file_list.total_methods).to be_a(Integer)
      expect(branch_method_file_list.covered_methods).to be_a(Integer)
      expect(branch_method_file_list.missed_methods).to be_a(Integer)
      expect(branch_method_file_list.method_covered_percent).to be_a(Float)
    end
  end

  describe "when :line coverage is disabled" do
    # When the user runs branch-only (or method-only), the FileList's
    # legacy line-coverage accessors should return nil rather than
    # crashing on the absent `:line` key in coverage_statistics.
    let(:branch_only_file_list) do
      branch_stat = SimpleCov::CoverageStatistics.new(covered: 1, missed: 1)
      source_file = instance_double(SimpleCov::SourceFile,
                                    coverage_statistics: {branch: branch_stat})
      described_class.new([source_file])
    end

    before do
      allow(SimpleCov).to receive_messages(branch_coverage?: true, method_coverage?: false)
      allow(SimpleCov).to receive(:coverage_criterion_enabled?).with(:line).and_return(false)
      allow(SimpleCov).to receive(:coverage_criterion_enabled?).with(:oneshot_line).and_return(false)
    end

    it "returns nil from line-coverage accessors" do
      expect(branch_only_file_list.covered_lines).to be_nil
      expect(branch_only_file_list.missed_lines).to be_nil
      expect(branch_only_file_list.lines_of_code).to be_nil
      expect(branch_only_file_list.covered_percent).to be_nil
      expect(branch_only_file_list.covered_strength).to be_nil
    end

    it "omits :line from enabled_criteria_for_reporting" do
      expect(branch_only_file_list.send(:enabled_criteria_for_reporting)).to contain_exactly(:branch)
    end
  end
end
