# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ExitCodes::MinimumCoverageByGroupCheck,
  mutant_expression: ["SimpleCov::ExitCodes::MinimumCoverageByGroupCheck*",
    "SimpleCov::CoverageViolations*"] do
  subject(:check) { described_class.new(result, minimum_coverage_by_group) }

  let(:coverage_statistics) { {line: SimpleCov::CoverageStatistics.new(covered: 8, missed: 2), branch: SimpleCov::CoverageStatistics.new(covered: 8, missed: 2)} }
  let(:result) { instance_double(SimpleCov::Result, groups: {"Test Group 1" => instance_double(SimpleCov::FileList, coverage_statistics: coverage_statistics)}) }
  let(:stats) { {"Test Group 1" => coverage_statistics} }

  context "when everything exactly ok" do
    let(:minimum_coverage_by_group) { {"Test Group 1" => {line: 80.0}} }

    it { is_expected.not_to be_failing }
  end

  context "when coverage violated" do
    let(:minimum_coverage_by_group) { {"Test Group 1" => {line: 90.0}} }

    it { is_expected.to be_failing }
  end

  context "when coverage slightly violated" do
    let(:minimum_coverage_by_group) { {"Test Group 1" => {line: 80.01}} }

    it { is_expected.to be_failing }
  end

  context "when one criterion violated" do
    let(:minimum_coverage_by_group) { {"Test Group 1" => {line: 80.0, branch: 90.0}} }

    it { is_expected.to be_failing }
  end

  context "when group does not exist in result" do
    let(:minimum_coverage_by_group) { {"Nonexistent Group" => {line: 80.0}} }

    it "warns about the missing group and does not fail" do
      expect { check.failing? }.to output(
        /minimum_coverage_by_group: no group named 'Nonexistent Group' exists/
      ).to_stderr
      expect(check).not_to be_failing
    end

    it "stays silent about the missing group when print_errors is off" do
      allow(SimpleCov).to receive(:print_errors).and_return(false)

      expect { check.failing? }.not_to output.to_stderr
    end
  end

  describe "#report" do
    let(:minimum_coverage_by_group) { {"Test Group 1" => {line: 90.0}} }

    it "prints the violating group with criterion and percentage" do
      output = check.report_lines.join("
")
      expect(output).to include("Line coverage by group")
      expect(output).to include("Test Group 1")
    end
  end

  describe "#exit_code" do
    let(:minimum_coverage_by_group) { {"Test Group 1" => {line: 80.0}} }

    it "returns SimpleCov::ExitCodes::MINIMUM_COVERAGE" do
      expect(check.exit_code).to eq(SimpleCov::ExitCodes::MINIMUM_COVERAGE)
    end
  end

  it "names the group that fell short, and by how much" do
    allow(SimpleCov::Color).to receive(:enabled?).and_return(false)

    expect(described_class.new(result, {"Test Group 1" => {line: 90.0}}).report_lines)
      .to eq(["Line coverage by group (80.00%) is below the expected minimum coverage " \
              "(90.00%) in Test Group 1."])
  end
end
