# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ExitCodes::ExitCodeHandling do
  subject(:exit_status) { described_class.call(result, coverage_limits: coverage_limits) }

  let(:result) { instance_double(SimpleCov::Result) }
  # `coverage_limits` is forwarded only to `coverage_checks`, which we
  # stub out — so its shape doesn't matter for these specs.
  let(:coverage_limits) { double }

  context "when a check fails" do
    let(:failing_check) do
      instance_double(
        SimpleCov::ExitCodes::MinimumOverallCoverageCheck,
        failing?: true,
        exit_code: SimpleCov::ExitCodes::MINIMUM_COVERAGE,
        report: nil
      )
    end

    before do
      allow(described_class).to receive(:coverage_checks).and_return([failing_check])
    end

    it "returns the failing check's exit code" do
      expect(exit_status).to eq(SimpleCov::ExitCodes::MINIMUM_COVERAGE)
    end

    it "reports the violation when print_errors is true" do
      allow(SimpleCov).to receive(:print_errors).and_return(true)
      exit_status
      expect(failing_check).to have_received(:report)
    end

    it "stays silent when print_errors is false but still returns the exit code" do
      allow(SimpleCov).to receive(:print_errors).and_return(false)
      expect(exit_status).to eq(SimpleCov::ExitCodes::MINIMUM_COVERAGE)
      expect(failing_check).not_to have_received(:report)
    end
  end

  describe ".coverage_checks" do
    let(:coverage_limits) do
      double(
        minimum_coverage: {}, minimum_coverage_by_file: {}, minimum_coverage_by_file_overrides: {},
        minimum_coverage_by_group: {}, maximum_coverage: {}, maximum_coverage_drop: {},
        maximum_missed: {}, maximum_missed_per_file: {}, maximum_missed_per_file_overrides: {},
        baseline: nil
      )
    end

    it "includes the baseline and missed-cap checks" do
      checks = described_class.coverage_checks(result, coverage_limits)
      expect(checks.map(&:class)).to include(
        SimpleCov::ExitCodes::BaselineCheck,
        SimpleCov::ExitCodes::MaximumMissedCheck,
        SimpleCov::ExitCodes::MaximumMissedPerFileCheck
      )
    end
  end

  context "when every check passes" do
    let(:passing_check) do
      instance_double(SimpleCov::ExitCodes::MinimumOverallCoverageCheck, failing?: false)
    end

    before do
      allow(described_class).to receive(:coverage_checks).and_return([passing_check])
    end

    it "returns SUCCESS" do
      expect(exit_status).to eq(SimpleCov::ExitCodes::SUCCESS)
    end
  end
end
