# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ExitCodes::MinimumOverallCoverageCheck,
  mutant_expression: ["SimpleCov::ExitCodes::MinimumOverallCoverageCheck*",
    "SimpleCov::CoverageViolations*"] do
  subject(:check) { described_class.new(result, minimum_coverage) }

  let(:result) do
    instance_double(SimpleCov::Result, coverage_statistics: stats, files: files)
  end
  let(:stats) do
    {
      line: SimpleCov::CoverageStatistics.new(covered: 8, missed: 2),
      branch: SimpleCov::CoverageStatistics.new(covered: 8, missed: 2)
    }
  end
  let(:files) { [] }

  context "when everything exactly ok" do
    let(:minimum_coverage) { {line: 80.0} }

    it { is_expected.not_to be_failing }
  end

  context "when coverage violated" do
    let(:minimum_coverage) { {line: 90.0} }

    it { is_expected.to be_failing }
  end

  context "when coverage slightly violated" do
    let(:minimum_coverage) { {line: 80.01} }

    it { is_expected.to be_failing }
  end

  context "when one criterion violated" do
    let(:minimum_coverage) { {line: 80.0, branch: 90.0} }

    it { is_expected.to be_failing }
  end

  context "when threshold uses :oneshot_line" do
    let(:minimum_coverage) { {oneshot_line: 90.0} }

    it { is_expected.to be_failing }

    it "doesn't raise when computing violations" do
      expect { check.failing? }.not_to raise_error
    end
  end

  describe "#report" do
    let(:minimum_coverage) { {line: 90.0} }
    let(:files) do
      [
        file_double("lib/best.rb", line: 95.0),
        file_double("lib/middle.rb", line: 80.0),
        file_double("lib/worst.rb", line: 10.0)
      ]
    end

    def file_double(path, percentages)
      file_stats = percentages.transform_values do |pct|
        instance_double(SimpleCov::CoverageStatistics, percent: pct)
      end
      instance_double(SimpleCov::SourceFile, project_filename: path, coverage_statistics: file_stats)
    end

    it "prints the violation and the lowest-coverage files for the criterion" do
      output = check.report_lines.join("
")
      expect(output).to include("Line coverage")
      expect(output).to include("Lowest-coverage files (line):")
      expect(output).to include("lib/worst.rb")
      expect(output).to include("lib/middle.rb")
      expect(output.index("lib/worst.rb")).to be < output.index("lib/middle.rb")
    end

    it "leaves fully covered files out of the list" do
      result_files = files + [file_double("lib/covered.rb", line: 100.0)]
      allow(result).to receive(:files).and_return(result_files)

      output = check.report_lines.join("
")
      expect(output).not_to include("lib/covered.rb")
    end

    it "skips files that lack stats for the violated criterion" do
      missing = instance_double(SimpleCov::SourceFile, project_filename: "lib/missing.rb", coverage_statistics: {})
      result_files = files + [missing]
      allow(result).to receive(:files).and_return(result_files)

      output = check.report_lines.join("
")
      expect(output).not_to include("lib/missing.rb")
    end
  end

  it "fails the run with the minimum-coverage code" do
    expect(described_class.new(result, {line: 90.0}).exit_code).to eq(SimpleCov::ExitCodes::MINIMUM_COVERAGE)
  end

  describe "the lowest-coverage hint" do
    def source_file(path, percent)
      instance_double(
        SimpleCov::SourceFile, project_filename: path,
        coverage_statistics: {line: instance_double(SimpleCov::CoverageStatistics, percent: percent)}
      )
    end

    let(:minimum_coverage) { {line: 90.0} }
    let(:files) do
      [source_file("f.rb", 60.0), source_file("b.rb", 20.0), source_file("e.rb", 50.0),
        source_file("a.rb", 10.0), source_file("d.rb", 40.0), source_file("c.rb", 30.0),
        source_file("whole.rb", 100.0), source_file("nearly.rb", 99.5)]
    end

    it "names the five lowest, and only files with something missing" do
      expect(check.send(:worst_files_for, :line))
        .to eq([["a.rb", 10.0], ["b.rb", 20.0], ["c.rb", 30.0], ["d.rb", 40.0], ["e.rb", 50.0]])
    end

    it "keeps a file that is short by a fraction" do
      allow(result).to receive(:files).and_return([source_file("nearly.rb", 99.5)])
      expect(check.send(:worst_files_for, :line)).to eq([["nearly.rb", 99.5]])
    end

    it "reads oneshot line coverage from the line statistics" do
      allow(result).to receive(:files).and_return([source_file("a.rb", 10.0)])
      expect(check.send(:worst_files_for, :oneshot_line)).to eq([["a.rb", 10.0]])
    end

    it "renders each of them under a heading, aligned" do
      allow(result).to receive(:files).and_return([source_file("a.rb", 10.0)])
      allow(SimpleCov::Color).to receive(:enabled?).and_return(false)

      expect(check.send(:worst_files_lines, :line))
        .to eq(["  Lowest-coverage files (line):", "     10.00%  a.rb"])
    end

    it "renders nothing when every file is covered" do
      allow(result).to receive(:files).and_return([source_file("whole.rb", 100.0)])
      expect(check.send(:worst_files_lines, :line)).to eq([])
    end
  end

  it "reports what fell short, and by how much" do
    allow(SimpleCov::Color).to receive(:enabled?).and_return(false)

    expect(described_class.new(result, {line: 90.0}).report_lines)
      .to eq(["Line coverage (80.00%) is below the expected minimum coverage (90.00%)."])
  end
end
