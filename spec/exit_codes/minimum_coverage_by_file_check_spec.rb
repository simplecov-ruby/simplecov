# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ExitCodes::MinimumCoverageByFileCheck do
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

    it "prints the violating file with criterion and percentage" do
      output = capture_stderr { check.report }
      expect(output).to include("Line coverage by file")
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

    context "when an override raises the bar for one specific file" do
      let(:overrides) { {"lib/critical.rb" => {line: 100}} }

      it "fails because the override is violated" do
        expect(check).to be_failing
      end

      it "names the file under the override threshold in the report" do
        output = capture_stderr { check.report }
        expect(output).to include("lib/critical.rb")
        expect(output).to include("(100.00%)")
        expect(output).not_to include("lib/regular.rb")
      end
    end

    context "when an exact-path override does not match" do
      # "lib/critical" without `.rb` is not equal to "lib/critical.rb", so
      # the override doesn't apply and the default of 70 passes.
      let(:overrides) { {"lib/critical" => {line: 100}} }

      it { is_expected.not_to be_failing }
    end

    context "with a directory-prefix override (trailing slash)" do
      let(:overrides) { {"lib/" => {line: 100}} }

      it "applies the override to every file under that directory" do
        expect(check).to be_failing
        output = capture_stderr { check.report }
        expect(output).to include("lib/regular.rb")
        expect(output).to include("lib/critical.rb")
      end
    end

    context "with a Regexp override" do
      let(:overrides) { {/critical/ => {line: 100}} }

      it "matches only files whose project path matches the Regexp" do
        expect(check).to be_failing
        output = capture_stderr { check.report }
        expect(output).to include("lib/critical.rb")
        expect(output).not_to include("lib/regular.rb")
      end
    end

    context "when two overrides match the same file" do
      # Later declarations win per criterion (overrides merge in order),
      # so the per-file override of 100 takes precedence over the
      # broader directory override of 90.
      let(:overrides) { {"lib/" => {line: 90}, "lib/critical.rb" => {line: 100}} }

      it "uses the override declared last" do
        expect(check).to be_failing
        output = capture_stderr { check.report }
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
      # Default holds branch at 50; override raises line to 100. Both
      # criteria are checked against the file (merge semantics).
      let(:minimum_coverage_by_file) { {line: 70, branch: 50} }
      let(:overrides) { {"lib/critical.rb" => {line: 100}} }

      it "merges defaults with override (override wins per criterion)" do
        expect(check).to be_failing
        output = capture_stderr { check.report }
        # The file's branch at 60% passes the default 50% threshold.
        expect(output).not_to include("Branch coverage")
        # The file's line at 80% fails the override 100% threshold.
        expect(output).to include("Line coverage")
        expect(output).to include("(100.00%)")
      end
    end
  end
end
