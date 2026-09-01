# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ExitCodes::MaximumCoverageDropCheck,
  mutant_expression: ["SimpleCov::ExitCodes::MaximumCoverageDropCheck*",
    "SimpleCov::CoverageViolations*"] do
  subject(:check) { described_class.new(result, maximum_coverage_drop) }

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
    allow(SimpleCov::LastRun).to receive(:read).and_return(last_run)
  end

  context "when we're at the same coverage" do
    it { is_expected.not_to be_failing }
  end

  context "when more coverage drop allowed" do
    let(:maximum_coverage_drop) { {line: 10, branch: 10} }

    it { is_expected.not_to be_failing }
  end

  context "when last coverage lower then new coverage" do
    let(:last_coverage) { {line: 70.0, branch: 70.0} }

    it { is_expected.not_to be_failing }
  end

  context "when last coverage higher than new coverage" do
    let(:last_coverage) { {line: 80.01, branch: 80.01} }

    it { is_expected.to be_failing }

    context "when allowed drop is within range" do
      let(:maximum_coverage_drop) { {line: 0.01, branch: 0.01} }

      it { is_expected.not_to be_failing }
    end
  end

  context "when one coverage lower than maximum drop" do
    let(:last_coverage) { {line: 80.01, branch: 70.0} }

    it { is_expected.to be_failing }

    context "when allowed drop is within range" do
      let(:maximum_coverage_drop) { {line: 0.01} }

      it { is_expected.not_to be_failing }
    end
  end

  context "when coverage expectation for a coverage that wasn't previously present" do
    let(:last_coverage) { {line: 80.0} }
    let(:maximum_coverage_drop) { {line: 0, branch: 0} }

    it { is_expected.not_to be_failing }
  end

  context "when no last run coverage information" do
    let(:last_run) { nil }

    it { is_expected.not_to be_failing }
  end

  context "when old last_run.json format" do
    let(:last_run) do
      {
        result: {covered_percent: 80.0}
      }
    end

    it { is_expected.not_to be_failing }
  end

  describe "#report" do
    let(:last_coverage) { {line: 90.0} }
    let(:maximum_coverage_drop) { {line: 5} }

    let(:output) { check.report_lines.join("\n") }

    it "names the criterion" do
      expect(output).to include("Line coverage")
    end

    it "says it dropped" do
      expect(output).to include("dropped")
    end

    it "says what the maximum allowed was" do
      expect(output).to include("maximum allowed")
    end
  end

  describe "#exit_code" do
    it "returns SimpleCov::ExitCodes::MAXIMUM_COVERAGE_DROP" do
      expect(check.exit_code).to eq(SimpleCov::ExitCodes::MAXIMUM_COVERAGE_DROP)
    end
  end

  context "when the run went backwards" do
    let(:last_coverage) { {line: 90.0, branch: 90.0} }

    it "reports the drop in red" do
      allow(SimpleCov::Color).to receive(:enabled?).and_return(true)

      expect(check.report_lines).to all(start_with("\e[31m").and(end_with("\e[0m")))
    end
  end
end
