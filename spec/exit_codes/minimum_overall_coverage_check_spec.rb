# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ExitCodes::MinimumOverallCoverageCheck do
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
    # `:oneshot_line` data is folded into the `:line` bucket of
    # `coverage_statistics`, so a threshold keyed on `:oneshot_line`
    # has to be looked up under `:line`. See issue #1170.
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
      output = capture_stderr { check.report }
      expect(output).to include("Line coverage")
      expect(output).to include("Lowest-coverage files (line):")
      expect(output).to include("lib/worst.rb")
      expect(output).to include("lib/middle.rb")
      # ascending order — worst first
      expect(output.index("lib/worst.rb")).to be < output.index("lib/middle.rb")
    end

    it "skips files that lack stats for the violated criterion" do
      missing = instance_double(SimpleCov::SourceFile, project_filename: "lib/missing.rb", coverage_statistics: {})
      result_files = files + [missing]
      allow(result).to receive(:files).and_return(result_files)

      output = capture_stderr { check.report }
      expect(output).not_to include("lib/missing.rb")
    end
  end
end
