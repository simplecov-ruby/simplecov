# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ExitCodes::ExitCodeHandling,
  mutant_expression: ["SimpleCov::ExitCodes::ExitCodeHandling*", "SimpleCov::CoverageViolations*"] do
  subject(:exit_status) { described_class.call(result, coverage_limits: coverage_limits) }

  let(:result) { instance_double(SimpleCov::Result) }
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

    it "builds the checks from the result and the limits it was given" do
      exit_status
      expect(described_class).to have_received(:coverage_checks).with(result, coverage_limits)
    end

    it "reports the violation when print_errors is true" do
      allow(SimpleCov).to receive(:print_errors).and_return(true)
      exit_status
      expect(failing_check).to have_received(:report)
    end

    it "still returns the exit code when print_errors is false" do
      allow(SimpleCov).to receive(:print_errors).and_return(false)

      expect(exit_status).to eq(SimpleCov::ExitCodes::MINIMUM_COVERAGE)
    end

    it "stays silent when print_errors is false" do
      allow(SimpleCov).to receive(:print_errors).and_return(false)
      exit_status

      expect(failing_check).not_to have_received(:report)
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

  describe ".coverage_checks" do
    let(:limits) do
      SimpleCov.singleton_class::CoverageLimits.new(
        minimum_coverage: {line: 90.0}, minimum_coverage_by_file: {line: 80.0},
        minimum_coverage_by_file_overrides: {"lib/a.rb" => {line: 10.0}},
        minimum_coverage_by_group: {"Libs" => {line: 70.0}},
        maximum_coverage: {line: 99.0}, maximum_coverage_drop: {line: 5.0},
        maximum_missed: {line: 3}, maximum_missed_per_file: {line: 2},
        maximum_missed_per_file_overrides: {"lib/b.rb" => {line: 9}},
        baseline: {"lib/c.rb" => {line: 1}}
      )
    end

    let(:checks) { described_class.coverage_checks(result, limits) }

    def expected_classes
      [
        SimpleCov::ExitCodes::MinimumOverallCoverageCheck,
        SimpleCov::ExitCodes::MinimumCoverageByFileCheck,
        SimpleCov::ExitCodes::BaselineCheck,
        SimpleCov::ExitCodes::MinimumCoverageByGroupCheck,
        SimpleCov::ExitCodes::MaximumOverallCoverageCheck,
        SimpleCov::ExitCodes::MaximumCoverageDropCheck,
        SimpleCov::ExitCodes::MaximumMissedCheck,
        SimpleCov::ExitCodes::MaximumMissedPerFileCheck
      ]
    end

    def expected_thresholds
      [
        {line: 90.0}, {line: 80.0}, nil,
        {"Libs" => {line: 70.0}},
        {line: 99.0}, {line: 5.0},
        {line: 3}, {line: 2}
      ]
    end

    it "builds each check in the order they are consulted" do
      expect(checks.map(&:class)).to eq(expected_classes)
    end

    it "hands every check the result it is to judge" do
      expect(checks.map { |check| check.send(:result) }).to all(be(result))
    end

    it "hands each check the limit it enforces" do
      expect(checks.map { |check| check.send(:thresholds) }).to eq(expected_thresholds)
    end

    it "hands the baseline check the baseline instead" do
      expect(checks.fetch(2).instance_variable_get(:@baseline)).to eq("lib/c.rb" => {line: 1})
    end

    it "hands the by-file check its overrides" do
      expect(checks.fetch(1).instance_variable_get(:@overrides)).to eq("lib/a.rb" => {line: 10.0})
    end

    it "hands the per-file check its overrides" do
      expect(checks.fetch(7).instance_variable_get(:@overrides)).to eq("lib/b.rb" => {line: 9})
    end

    it "hands both per-file checks the baseline" do
      expect(checks.values_at(1, 7).map { |check| check.instance_variable_get(:@baseline) })
        .to all(eq("lib/c.rb" => {line: 1}))
    end
  end
end
