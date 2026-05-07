# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ExitCodes::MinimumCoverageByFileCheck do
  subject(:check) { described_class.new(result, minimum_coverage_by_file) }

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
end
