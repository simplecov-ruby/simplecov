# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ExitCodes::MinimumCoverageByFileCheck do
  subject { described_class.new(result, minimum_coverage_by_file) }

  let(:result) do
    instance_double(SimpleCov::Result, coverage_statistics_by_file: stats)
  end
  let(:stats) do
    {
      line: [SimpleCov::CoverageStatistics.new(covered: 8, missed: 2)]
    }
  end

  context "all files passing requirements" do
    let(:minimum_coverage_by_file) { {line: 80} }

    it { is_expected.not_to be_failing }
  end

  context "one file violating requirements" do
    let(:minimum_coverage_by_file) { {line: 90} }

    it { is_expected.to be_failing }
  end
end
