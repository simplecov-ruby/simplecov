# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ExitCodes::MinimumOverallCoverageCheck do
  subject { described_class.new(result, minimum_coverage) }

  let(:result) do
    instance_double(SimpleCov::Result, coverage_statistics: stats)
  end
  let(:stats) do
    {
      line: SimpleCov::CoverageStatistics.new(covered: 8, missed: 2),
      branch: SimpleCov::CoverageStatistics.new(covered: 8, missed: 2)
    }
  end

  context "everything exactly ok" do
    let(:minimum_coverage) { {line: 80.0} }

    it { is_expected.not_to be_failing }
  end

  context "coverage violated" do
    let(:minimum_coverage) { {line: 90.0} }

    it { is_expected.to be_failing }
  end

  context "coverage slightly violated" do
    let(:minimum_coverage) { {line: 80.01} }

    it { is_expected.to be_failing }
  end

  context "one criterion violated" do
    let(:minimum_coverage) { {line: 80.0, branch: 90.0} }

    it { is_expected.to be_failing }
  end
end
