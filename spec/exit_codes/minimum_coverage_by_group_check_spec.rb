# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ExitCodes::MinimumCoverageByGroupCheck do
  subject { described_class.new(result, minimum_coverage_by_group) }

  let(:coverage_statistics) { {line: SimpleCov::CoverageStatistics.new(covered: 8, missed: 2), branch: SimpleCov::CoverageStatistics.new(covered: 8, missed: 2)} }
  let(:result) { instance_double(SimpleCov::Result, groups: {"Test Group 1" => instance_double(SimpleCov::FileList, coverage_statistics: coverage_statistics)}) }
  let(:stats) { {"Test Group 1" => coverage_statistics} }

  context "everything exactly ok" do
    let(:minimum_coverage_by_group) { {"Test Group 1" => {line: 80.0}} }

    it { is_expected.not_to be_failing }
  end

  context "coverage violated" do
    let(:minimum_coverage_by_group) { {"Test Group 1" => {line: 90.0}} }

    it { is_expected.to be_failing }
  end

  context "coverage slightly violated" do
    let(:minimum_coverage_by_group) { {"Test Group 1" => {line: 80.01}} }

    it { is_expected.to be_failing }
  end

  context "one criterion violated" do
    let(:minimum_coverage_by_group) { {"Test Group 1" => {line: 80.0, branch: 90.0}} }

    it { is_expected.to be_failing }
  end

  context "group does not exist in result" do
    let(:minimum_coverage_by_group) { {"Nonexistent Group" => {line: 80.0}} }

    it "warns about the missing group and does not fail" do
      expect { subject.failing? }.to output(
        /minimum_coverage_by_group: no group named 'Nonexistent Group' exists/
      ).to_stderr
      expect(subject).not_to be_failing
    end
  end
end
