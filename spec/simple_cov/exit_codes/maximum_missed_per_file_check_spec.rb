# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ExitCodes::MaximumMissedPerFileCheck,
  mutant_expression: ["SimpleCov::ExitCodes::MaximumMissedPerFileCheck*",
    "SimpleCov::CoverageViolations*"] do
  subject(:check) { described_class.new(result, maximum_missed_per_file, overrides, baseline: baseline) }

  let(:result) { instance_double(SimpleCov::Result, files: files) }
  let(:files) do
    [
      instance_double(
        SimpleCov::SourceFile,
        coverage_statistics: {line: SimpleCov::CoverageStatistics.new(covered: 15, missed: 5)},
        filename: "/abs/lib/foo.rb",
        project_filename: "lib/foo.rb"
      )
    ]
  end
  let(:overrides) { {} }
  let(:baseline) { nil }

  context "when every file is within the cap" do
    let(:maximum_missed_per_file) { {line: 5} }

    it { is_expected.not_to be_failing }
  end

  context "when a file exceeds the cap" do
    let(:maximum_missed_per_file) { {line: 4} }
    let(:output) { check.report_lines.join("\n") }

    it { is_expected.to be_failing }

    it "reports the count in the criterion's own units" do
      expect(output).to include("Missed lines (5)")
    end

    it "reports the cap it passed" do
      expect(output).to include("maximum_missed_per_file (4)")
    end

    it "names the file" do
      expect(output).to include("lib/foo.rb")
    end
  end

  context "with a per-path override" do
    let(:maximum_missed_per_file) { {line: 10} }
    let(:overrides) { {"lib/foo.rb" => {line: 0}} }

    it "applies the override to the matching file" do
      expect(check).to be_failing
    end
  end

  context "when the file's criterion is covered by the baseline" do
    let(:maximum_missed_per_file) { {line: 0} }
    let(:baseline) do
      SimpleCov::Baseline.new(
        "lib/foo.rb" => {line: SimpleCov::Baseline::Floor.new(percent: 75.0, missed: 5)}
      )
    end

    it { is_expected.not_to be_failing }
  end

  context "when the baseline covers a different criterion" do
    let(:maximum_missed_per_file) { {line: 0} }
    let(:baseline) do
      SimpleCov::Baseline.new(
        "lib/foo.rb" => {branch: SimpleCov::Baseline::Floor.new(percent: 75.0, missed: 5)}
      )
    end

    it { is_expected.to be_failing }
  end

  describe "#exit_code" do
    let(:maximum_missed_per_file) { {line: 0} }

    it "returns MINIMUM_COVERAGE" do
      expect(check.exit_code).to eq(SimpleCov::ExitCodes::MINIMUM_COVERAGE)
    end
  end

  describe "a check built with neither overrides nor a baseline" do
    let(:built) { described_class.new(result, {line: 2}) }

    it "defaults the overrides to none" do
      expect(built.instance_variable_get(:@overrides)).to eq({})
    end

    it "defaults the baseline to none" do
      expect(built.instance_variable_get(:@baseline)).to be_nil
    end

    it "still checks the cap" do
      expect(built).to be_failing
    end
  end

  it "names the file, its misses and the cap they passed" do
    expect(described_class.new(result, {line: 2}).report_lines)
      .to eq(["Missed lines (5) exceed the configured maximum_missed_per_file (2) in lib/foo.rb."])
  end

  it "names oneshot lines as lines" do
    violation = {criterion: :oneshot_line, actual: 5, maximum: 2, project_filename: "lib/foo.rb"}

    expect(described_class.new(result, {line: 2}).send(:violation_lines, violation))
      .to eq(["Missed lines (5) exceed the configured maximum_missed_per_file (2) in lib/foo.rb."])
  end
end
