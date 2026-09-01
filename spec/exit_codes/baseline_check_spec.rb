# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ExitCodes::BaselineCheck,
  mutant_expression: ["SimpleCov::ExitCodes::BaselineCheck*", "SimpleCov::CoverageViolations*"] do
  subject(:check) { described_class.new(result, baseline) }

  let(:result) { instance_double(SimpleCov::Result, files: files) }
  let(:files) do
    [
      instance_double(
        SimpleCov::SourceFile,
        coverage_statistics: coverage_statistics,
        filename: "/abs/lib/foo.rb",
        project_filename: "lib/foo.rb"
      )
    ]
  end
  let(:coverage_statistics) { {line: SimpleCov::CoverageStatistics.new(covered: 8, missed: 2)} }

  let(:baseline) do
    SimpleCov::Baseline.new(
      "lib/foo.rb" => {line: SimpleCov::Baseline::Floor.new(percent: floor_percent, missed: floor_missed)}
    )
  end
  let(:floor_percent) { 80.0 }
  let(:floor_missed) { 2 }

  context "with no baseline" do
    let(:baseline) { nil }

    it { is_expected.not_to be_failing }
  end

  context "when the file sits exactly at its floor" do
    it { is_expected.not_to be_failing }
  end

  context "when the file is above its floor" do
    let(:floor_percent) { 70.0 }
    let(:floor_missed) { 3 }

    it { is_expected.not_to be_failing }
  end

  context "when the file dropped below its floor on both axes" do
    let(:floor_percent) { 90.0 }
    let(:floor_missed) { 1 }

    it { is_expected.to be_failing }

    it "names the file, the floor, and both measurements" do
      output = check.report_lines.join("
")
      expect(output).to include("lib/foo.rb")
      expect(output).to include("90.0%")
      expect(output).to include("2 uncovered lines")
      expect(output).to include("1 allowed")
    end
  end

  context "when the percent dropped but the missed count did not grow" do
    let(:floor_percent) { 90.0 }
    let(:floor_missed) { 2 }

    it { is_expected.not_to be_failing }
  end

  context "with a percent-only floor" do
    let(:floor_missed) { nil }
    let(:floor_percent) { 90.0 }

    it "fails on the percent alone" do
      expect(check).to be_failing
    end

    it "reports without the missed clause, which was never recorded" do
      output = check.report_lines.join("
")
      expect(output).to include("lib/foo.rb")
      expect(output).not_to include("allowed")
    end
  end

  context "when the baseline covers a criterion the run did not measure" do
    let(:baseline) do
      SimpleCov::Baseline.new(
        "lib/foo.rb" => {branch: SimpleCov::Baseline::Floor.new(percent: 90.0, missed: 0)}
      )
    end
    let(:coverage_statistics) { {line: SimpleCov::CoverageStatistics.new(covered: 8, missed: 2)} }

    it { is_expected.not_to be_failing }
  end

  context "with a file the baseline does not cover" do
    let(:baseline) do
      SimpleCov::Baseline.new(
        "lib/other.rb" => {line: SimpleCov::Baseline::Floor.new(percent: 100.0, missed: 0)}
      )
    end

    it { is_expected.not_to be_failing }
  end

  describe "#exit_code" do
    it "returns MINIMUM_COVERAGE" do
      expect(check.exit_code).to eq(SimpleCov::ExitCodes::MINIMUM_COVERAGE)
    end
  end

  describe "criterion wording" do
    let(:coverage_statistics) do
      {
        line: SimpleCov::CoverageStatistics.new(covered: 10, missed: 0),
        branch: SimpleCov::CoverageStatistics.new(covered: 1, missed: 3)
      }
    end
    let(:baseline) do
      SimpleCov::Baseline.new(
        "lib/foo.rb" => {branch: SimpleCov::Baseline::Floor.new(percent: 75.0, missed: 1)}
      )
    end

    it "speaks in the violated criterion's own units" do
      output = check.report_lines.join("
")
      expect(output).to include("Branch coverage")
      expect(output).to include("3 uncovered branches")
    end
  end

  it "carries the baseline rather than a threshold" do
    expect(check.send(:thresholds)).to be_nil
    expect(check.instance_variable_get(:@baseline)).to be(baseline)
  end

  describe "what it reports" do
    let(:floor_percent) { 90.0 }
    let(:floor_missed) { 1 }

    before { allow(SimpleCov::Color).to receive(:enabled?).and_return(false) }

    it "names the file, the coverage reached and the floor it fell under" do
      expect(check.report_lines)
        .to eq(["Line coverage (80.00%) dropped below its baseline floor (90.0%) in lib/foo.rb " \
                "(2 uncovered lines, 1 allowed)."])
    end

    it "names oneshot lines as lines" do
      violation = {criterion: :oneshot_line, allowed_missed: 1, actual_missed: 2}

      expect(check.send(:missed_clause, violation)).to eq(" (2 uncovered lines, 1 allowed)")
    end

    it "says nothing about misses where no count was recorded" do
      expect(check.send(:missed_clause, {criterion: :line, allowed_missed: nil})).to be_nil
    end
  end
end
