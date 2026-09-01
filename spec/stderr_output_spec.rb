# frozen_string_literal: true

require "helper"

RSpec.describe "stderr output contract" do
  before { allow(Warning).to receive(:warn).and_call_original }

  def expect_no_warning
    expect(Warning).not_to have_received(:warn)
  end

  describe "threshold enforcement output" do
    let(:check_result) do
      instance_double(
        SimpleCov::Result,
        coverage_statistics: {line: SimpleCov::CoverageStatistics.new(covered: 8, missed: 2)},
        files: []
      )
    end
    let(:check) do
      SimpleCov::ExitCodes::MinimumOverallCoverageCheck.new(check_result, {line: 90.0})
    end

    it "reports violations to stderr without engaging Warning.warn" do
      expect { check.report }
        .to output(/Line coverage.+below the expected minimum coverage/m).to_stderr
      expect_no_warning
    end

    context "when Ruby warnings are disabled (-W0)" do
      around do |example|
        verbose = $VERBOSE
        $VERBOSE = nil
        example.run
      ensure
        $VERBOSE = verbose
      end

      it "still reports violations" do
        expect { check.report }.to output(/below the expected minimum coverage/).to_stderr
      end
    end
  end
end
