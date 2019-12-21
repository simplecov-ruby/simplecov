# frozen_string_literal: true

require "helper"

describe SimpleCov::Configuration do
  let(:config_class) do
    Class.new do
      include SimpleCov::Configuration
    end
  end
  let(:config) { config_class.new }

  describe "#print_error_status" do
    subject { config.print_error_status }

    context "when not manually set" do
      it { is_expected.to be true }
    end

    context "when manually set" do
      before { config.print_error_status = false }
      it { is_expected.to be false }
    end
  end

  describe "#tracked_files" do
    context "when configured" do
      let(:glob) { "{app,lib}/**/*.rb" }
      before { config.track_files(glob) }

      it "returns the configured glob" do
        expect(config.tracked_files).to eq glob
      end

      context "and configured again with nil" do
        before { config.track_files(nil) }

        it "returns nil" do
          expect(config.tracked_files).to be_nil
        end
      end
    end

    context "when unconfigured" do
      it "returns nil" do
        expect(config.tracked_files).to be_nil
      end
    end

    describe "#minimum_coverage" do
      it "does not warn you about your usage" do
        expect(config).not_to receive(:warn)
        config.minimum_coverage(100.00)
      end

      it "warns you about your usage" do
        expect(config).to receive(:warn).with("The coverage you set for minimum_coverage is greater than 100%")
        config.minimum_coverage(100.01)
      end
    end

    describe "#minimum_coverage_by_file" do
      it "does not warn you about your usage" do
        expect(config).not_to receive(:warn)
        config.minimum_coverage_by_file(100.00)
      end

      it "warns you about your usage" do
        expect(config).to receive(:warn).with("The coverage you set for minimum_coverage_by_file is greater than 100%")
        config.minimum_coverage_by_file(100.01)
      end
    end

    describe "#coverage_criterion" do
      it "defaults to line" do
        expect(config.coverage_criterion).to eq :line
      end

      it "works fine with line" do
        config.coverage_criterion :line

        expect(config.coverage_criterion).to eq :line
      end

      it "works fine with :branch" do
        config.coverage_criterion :branch

        expect(config.coverage_criterion).to eq :branch
      end

      it "errors out on unknown coverage" do
        expect do
          config.coverage_criterion :unknown
        end.to raise_error(/unsupported.*unknown.*line/i)
      end
    end

    describe "#branch_coverage?", :if => SimpleCov.branch_coverage_supported? do
      it "returns true of branch coverage is being measured" do
        config.coverage_criterion :branch

        expect(config).to be_branch_coverage
      end

      it "returns false for line coverage" do
        config.coverage_criterion :line

        expect(config).not_to be_branch_coverage
      end
    end
  end
end
