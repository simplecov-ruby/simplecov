# frozen_string_literal: true

require "helper"

# Status lines and threshold-enforcement output are deliberately written
# with `$stderr.puts` rather than `Kernel#warn`: they are program output,
# not Ruby warnings, so `Warning.warn` hooks (warning trackers,
# raise-on-warning test setups) must not intercept them and `-W0` must not
# swallow them. See #1225.
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

    # No Warning assertion here: under `-W0`, `Kernel#warn` returns without
    # ever reaching `Warning.warn`, so only the output assertion can tell
    # `$stderr.puts` (prints) apart from `warn` (silently dropped).
    it "still reports violations when Ruby warnings are disabled (-W0)" do
      verbose = $VERBOSE
      $VERBOSE = nil
      begin
        expect { check.report }
          .to output(/below the expected minimum coverage/).to_stderr
      ensure
        $VERBOSE = verbose
      end
    end
  end
end
