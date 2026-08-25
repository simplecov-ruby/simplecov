# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ExitCodes::MaximumMissedPerFileCheck do
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

    it { is_expected.to be_failing }

    it "names the file with the counts" do
      output = capture_stderr { check.report }
      expect(output).to include("Missed lines (5)")
      expect(output).to include("maximum_missed_per_file (4)")
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

  # A baseline entry exempts the file and criterion the same way it
  # does for minimum_per_file: the file answers to its own floor.
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
end
