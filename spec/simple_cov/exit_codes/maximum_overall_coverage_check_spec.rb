# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ExitCodes::MaximumOverallCoverageCheck,
  mutant_expression: ["SimpleCov::ExitCodes::MaximumOverallCoverageCheck*",
    "SimpleCov::CoverageViolations*"] do
  subject(:check) { described_class.new(result, maximum_coverage) }

  let(:result) do
    instance_double(SimpleCov::Result, coverage_statistics: stats, files: [])
  end
  let(:stats) do
    {
      line: SimpleCov::CoverageStatistics.new(covered: 8, missed: 2),
      branch: SimpleCov::CoverageStatistics.new(covered: 8, missed: 2)
    }
  end

  context "when actual matches the maximum exactly" do
    let(:maximum_coverage) { {line: 80.0} }

    it { is_expected.not_to be_failing }
  end

  context "when actual is above the maximum" do
    let(:maximum_coverage) { {line: 70.0} }

    it { is_expected.to be_failing }
  end

  context "when one criterion violates" do
    let(:maximum_coverage) { {line: 90.0, branch: 70.0} }

    it { is_expected.to be_failing }
  end

  context "when actual is just inside the floor-to-two-decimals boundary" do
    let(:stats) do
      {line: instance_double(SimpleCov::CoverageStatistics, percent: 90.009)}
    end
    let(:maximum_coverage) { {line: 90.0} }

    it { is_expected.not_to be_failing }
  end

  context "when actual is just outside the floor-to-two-decimals boundary" do
    let(:stats) do
      {line: instance_double(SimpleCov::CoverageStatistics, percent: 90.01)}
    end
    let(:maximum_coverage) { {line: 90.0} }

    it { is_expected.to be_failing }
  end

  context "when threshold uses :oneshot_line" do
    let(:maximum_coverage) { {oneshot_line: 70.0} }

    it { is_expected.to be_failing }

    it "doesn't raise when computing violations" do
      expect { check.failing? }.not_to raise_error
    end
  end

  describe "#exit_code" do
    let(:maximum_coverage) { {line: 70.0} }

    it "returns SimpleCov::ExitCodes::MAXIMUM_COVERAGE" do
      expect(check.exit_code).to eq(SimpleCov::ExitCodes::MAXIMUM_COVERAGE)
    end
  end

  describe "#report" do
    let(:maximum_coverage) { {line: 70.0} }

    let(:output) { check.report_lines.join("\n") }

    it "names the criterion" do
      expect(output).to include("Line coverage")
    end

    it "says it rose above the ceiling" do
      expect(output).to include("above the expected maximum coverage")
    end

    it "invites raising the ceiling" do
      expect(output).to include("Time to bump the threshold!")
    end
  end

  it "reports what rose above the ceiling, and invites raising it" do
    allow(SimpleCov::Color).to receive(:enabled?).and_return(false)

    expect(described_class.new(result, {line: 70.0}).report_lines)
      .to eq(["Line coverage (80.00%) is above the expected maximum coverage (70.00%). " \
              "Time to bump the threshold!"])
  end
end
