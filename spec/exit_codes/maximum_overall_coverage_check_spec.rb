# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ExitCodes::MaximumOverallCoverageCheck do
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
    # floor(90.009, 2) == 90.00, which is not > 90.0 → passes.
    let(:stats) do
      {line: instance_double(SimpleCov::CoverageStatistics, percent: 90.009)}
    end
    let(:maximum_coverage) { {line: 90.0} }

    it { is_expected.not_to be_failing }
  end

  context "when actual is just outside the floor-to-two-decimals boundary" do
    # floor(90.01, 2) == 90.01 > 90.0 → fails.
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

    it "prints the violation with criterion and percentages, and a bump hint" do
      output = capture_stderr { check.report }
      expect(output).to include("Line coverage")
      expect(output).to include("above the expected maximum coverage")
      expect(output).to include("Time to bump the threshold!")
    end
  end
end
