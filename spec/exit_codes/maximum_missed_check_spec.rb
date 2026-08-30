# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ExitCodes::MaximumMissedCheck,
               mutant_expression: ["SimpleCov::ExitCodes::MaximumMissedCheck*", "SimpleCov::CoverageViolations*"] do
  subject(:check) { described_class.new(result, maximum_missed) }

  let(:result) do
    instance_double(
      SimpleCov::Result,
      coverage_statistics: {
        line: SimpleCov::CoverageStatistics.new(covered: 88, missed: 12),
        branch: SimpleCov::CoverageStatistics.new(covered: 7, missed: 3)
      }
    )
  end

  context "when the misses sit exactly at the cap" do
    let(:maximum_missed) { {line: 12} }

    it { is_expected.not_to be_failing }
  end

  context "when the misses exceed the cap" do
    let(:maximum_missed) { {line: 11} }

    it { is_expected.to be_failing }

    it "reports the count in the criterion's own units" do
      output = check.report_lines.join("
")
      expect(output).to include("Missed lines (12)")
      expect(output).to include("maximum_missed (11)")
    end
  end

  context "with a cap per criterion" do
    let(:maximum_missed) { {line: 100, branch: 2} }

    it "checks each criterion's own missed count" do
      expect(check).to be_failing
      output = check.report_lines.join("
")
      expect(output).to include("Missed branches (3)")
      expect(output).not_to include("lines")
    end
  end

  # Mirrors the percent checks: a criterion the runtime didn't measure
  # (e.g. branch caps under JRuby) is skipped rather than failed.
  context "when the capped criterion was not measured" do
    let(:result) do
      instance_double(
        SimpleCov::Result,
        coverage_statistics: {line: SimpleCov::CoverageStatistics.new(covered: 88, missed: 12)}
      )
    end
    let(:maximum_missed) { {branch: 0} }

    it { is_expected.not_to be_failing }
  end

  describe "#exit_code" do
    let(:maximum_missed) { {line: 0} }

    it "returns MINIMUM_COVERAGE" do
      expect(check.exit_code).to eq(SimpleCov::ExitCodes::MINIMUM_COVERAGE)
    end
  end

  it "reports the misses and the cap they passed, in the criterion's own units" do
    expect(described_class.new(result, {line: 10}).report_lines)
      .to eq(["Missed lines (12) exceed the configured maximum_missed (10)."])
  end

  # Oneshot lines are recorded under the line statistics, so their units
  # are read through the key they are stored under.
  it "names oneshot lines as lines" do
    expect(described_class.new(result, {oneshot_line: 10}).report_lines)
      .to eq(["Missed lines (12) exceed the configured maximum_missed (10)."])
  end
end
