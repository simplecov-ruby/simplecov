# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ExitCodes::MinimumCoverageByFileCheck,
  mutant_expression: ["SimpleCov::ExitCodes::MinimumCoverageByFileCheck*",
    "SimpleCov::CoverageViolations*"] do
  subject(:check) { described_class.new(result, minimum_coverage_by_file, overrides) }

  let(:result) do
    instance_double(SimpleCov::Result, files: files)
  end
  let(:coverage_statistics) { {line: SimpleCov::CoverageStatistics.new(covered: 8, missed: 2)} }
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
  let(:overrides) { {} }

  context "when all files passing requirements" do
    let(:minimum_coverage_by_file) { {line: 80} }

    it { is_expected.not_to be_failing }
  end

  context "when one file violating requirements" do
    let(:minimum_coverage_by_file) { {line: 90} }

    it { is_expected.to be_failing }
  end

  describe "#report" do
    let(:minimum_coverage_by_file) { {line: 90} }
    let(:output) { check.report_lines.join("\n") }

    it "names the criterion" do
      expect(output).to include("Line coverage by file")
    end

    it "names the violating file" do
      expect(output).to include("lib/foo.rb")
    end
  end

  describe "#exit_code" do
    let(:minimum_coverage_by_file) { {line: 80} }

    it "returns SimpleCov::ExitCodes::MINIMUM_COVERAGE" do
      expect(check.exit_code).to eq(SimpleCov::ExitCodes::MINIMUM_COVERAGE)
    end
  end

  describe "per-path overrides" do
    let(:files) do
      [
        instance_double(
          SimpleCov::SourceFile,
          coverage_statistics: {line: SimpleCov::CoverageStatistics.new(covered: 8, missed: 2)},
          filename: "/abs/lib/regular.rb",
          project_filename: "lib/regular.rb"
        ),
        instance_double(
          SimpleCov::SourceFile,
          coverage_statistics: {line: SimpleCov::CoverageStatistics.new(covered: 8, missed: 2)},
          filename: "/abs/lib/critical.rb",
          project_filename: "lib/critical.rb"
        )
      ]
    end
    let(:minimum_coverage_by_file) { {line: 70} }
    let(:output) { check.report_lines.join("\n") }

    context "when an override raises the bar for one specific file" do
      let(:overrides) { {"lib/critical.rb" => {line: 100}} }

      it "fails because the override is violated" do
        expect(check).to be_failing
      end

      it "names the file under the override threshold in the report" do
        expect(output).to include("lib/critical.rb")
      end

      it "names the override threshold it fell under" do
        expect(output).to include("(100.00%)")
      end

      it "leaves the files the override does not reach out of the report" do
        expect(output).not_to include("lib/regular.rb")
      end
    end

    context "when an exact-path override does not match" do
      let(:overrides) { {"lib/critical" => {line: 100}} }

      it { is_expected.not_to be_failing }
    end

    context "with a directory-prefix override (trailing slash)" do
      let(:overrides) { {"lib/" => {line: 100}} }

      it { is_expected.to be_failing }

      it "applies the override to one file under that directory" do
        expect(output).to include("lib/regular.rb")
      end

      it "applies it to the others too" do
        expect(output).to include("lib/critical.rb")
      end
    end

    context "with a Regexp override" do
      let(:overrides) { {/critical/ => {line: 100}} }

      it { is_expected.to be_failing }

      it "matches a file whose project path matches the Regexp" do
        expect(output).to include("lib/critical.rb")
      end

      it "matches no other file" do
        expect(output).not_to include("lib/regular.rb")
      end
    end

    context "when two overrides match the same file" do
      let(:overrides) { {"lib/" => {line: 90}, "lib/critical.rb" => {line: 100}} }

      it { is_expected.to be_failing }

      it "uses the override declared last" do
        expect(output).to include("(100.00%)")
      end
    end

    context "when override + defaults differ per criterion" do
      let(:coverage_statistics) do
        {
          line: SimpleCov::CoverageStatistics.new(covered: 8, missed: 2),
          branch: SimpleCov::CoverageStatistics.new(covered: 6, missed: 4)
        }
      end
      let(:files) do
        [
          instance_double(
            SimpleCov::SourceFile,
            coverage_statistics: coverage_statistics,
            filename: "/abs/lib/critical.rb",
            project_filename: "lib/critical.rb"
          )
        ]
      end
      let(:minimum_coverage_by_file) { {line: 70, branch: 50} }
      let(:overrides) { {"lib/critical.rb" => {line: 100}} }

      it { is_expected.to be_failing }

      it "keeps the criterion the override says nothing about within its default" do
        expect(output).not_to include("Branch coverage")
      end

      it "names the criterion the override raised" do
        expect(output).to include("Line coverage")
      end

      it "holds it to the override rather than the default" do
        expect(output).to include("(100.00%)")
      end
    end
  end

  describe "baseline exemption" do
    subject(:check) { described_class.new(result, minimum_coverage_by_file, overrides, baseline: baseline) }

    let(:minimum_coverage_by_file) { {line: 90} }

    context "when the failing file's criterion is covered by the baseline" do
      let(:baseline) do
        SimpleCov::Baseline.new(
          "lib/foo.rb" => {line: SimpleCov::Baseline::Floor.new(percent: 41.2, missed: 137)}
        )
      end

      it { is_expected.not_to be_failing }
    end

    context "when the baseline covers a different criterion of that file" do
      let(:baseline) do
        SimpleCov::Baseline.new(
          "lib/foo.rb" => {branch: SimpleCov::Baseline::Floor.new(percent: 41.2, missed: 137)}
        )
      end

      it { is_expected.to be_failing }
    end

    context "when the baseline covers a different file" do
      let(:baseline) do
        SimpleCov::Baseline.new(
          "lib/other.rb" => {line: SimpleCov::Baseline::Floor.new(percent: 41.2, missed: 137)}
        )
      end

      it { is_expected.to be_failing }
    end
  end

  describe "a check built with no overrides" do
    let(:built) { described_class.new(result, {line: 90.0}) }

    it "defaults them to none" do
      expect(built.instance_variable_get(:@overrides)).to eq({})
    end

    it "still checks the threshold" do
      expect(built).to be_failing
    end
  end

  it "names the file that fell short, and by how much" do
    allow(SimpleCov::Color).to receive(:enabled?).and_return(false)

    expect(described_class.new(result, {line: 90.0}).report_lines)
      .to eq(["Line coverage by file (80.00%) is below the expected minimum coverage " \
              "(90.00%) in lib/foo.rb."])
  end
end
