# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ExitCodes::MaximumCoverageDropCheck do
  subject { described_class.new(result, maximum_coverage_drop) }

  let(:result) do
    instance_double(SimpleCov::Result, coverage_statistics: stats)
  end
  let(:stats) do
    {
      line: SimpleCov::CoverageStatistics.new(covered: 8, missed: 2),
      branch: SimpleCov::CoverageStatistics.new(covered: 8, missed: 2)
    }
  end
  let(:last_run) do
    {
      result: last_coverage
    }
  end
  let(:last_coverage) { {line: 80.0, branch: 80.0} }
  let(:maximum_coverage_drop) { {line: 0, branch: 0} }

  before do
    expect(SimpleCov::LastRun).to receive(:read).and_return(last_run)
  end

  context "we're at the same coverage" do
    it { is_expected.not_to be_failing }
  end

  context "more coverage drop allowed" do
    let(:maximum_coverage_drop) { {line: 10, branch: 10} }

    it { is_expected.not_to be_failing }
  end

  context "last coverage lower then new coverage" do
    let(:last_coverage) { {line: 70.0, branch: 70.0} }

    it { is_expected.not_to be_failing }
  end

  context "last coverage higher than new coverage" do
    let(:last_coverage) { {line: 80.01, branch: 80.01} }

    it { is_expected.to be_failing }

    context "but allowed drop is within range" do
      let(:maximum_coverage_drop) { {line: 0.01, branch: 0.01} }

      it { is_expected.not_to be_failing }
    end
  end

  context "one coverage lower than maximum drop" do
    let(:last_coverage) { {line: 80.01, branch: 70.0} }

    it { is_expected.to be_failing }

    context "but allowed drop is within range" do
      let(:maximum_coverage_drop) { {line: 0.01} }

      it { is_expected.not_to be_failing }
    end
  end

  context "coverage expectation for a coverage that wasn't previously present" do
    let(:last_coverage) { {line: 80.0} }
    let(:maximum_coverage_drop) { {line: 0, branch: 0} }

    it { is_expected.not_to be_failing }
  end

  context "no last run coverage information" do
    let(:last_run) { nil }

    it { is_expected.not_to be_failing }
  end

  context "old last_run.json format" do
    let(:last_run) do
      {
        # this format only considers line coverage
        result: {covered_percent: 80.0}
      }
    end

    it { is_expected.not_to be_failing }
  end
end
