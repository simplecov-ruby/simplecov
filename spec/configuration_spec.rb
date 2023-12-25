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

    shared_examples "setting coverage expectations" do |coverage_setting|
      after :each do
        config.clear_coverage_criteria
      end

      it "does not warn you about your usage" do
        expect(config).not_to receive(:warn)
        config.public_send(coverage_setting, 100.00)
      end

      it "warns you about your usage" do
        expect(config).to receive(:warn).with("The coverage you set for #{coverage_setting} is greater than 100%")
        config.public_send(coverage_setting, 100.01)
      end

      it "sets the right coverage value when called with a number" do
        config.public_send(coverage_setting, 80)

        expect(config.public_send(coverage_setting)).to eq line: 80
      end

      it "sets the right coverage when called with a hash of just line" do
        config.public_send(coverage_setting, {line: 85.0})

        expect(config.public_send(coverage_setting)).to eq line: 85.0
      end

      it "sets the right coverage when called with a hash of just branch" do
        config.enable_coverage :branch
        config.public_send(coverage_setting, {branch: 85.0})

        expect(config.public_send(coverage_setting)).to eq branch: 85.0
      end

      it "sets the right coverage when called with both line and branch" do
        config.enable_coverage :branch
        config.public_send(coverage_setting, {branch: 85.0, line: 95.4})

        expect(config.public_send(coverage_setting)).to eq branch: 85.0, line: 95.4
      end

      it "sets the right coverage when called with line, branch and method" do
        config.enable_coverage :branch
        config.enable_coverage :method
        config.minimum_coverage branch: 85.0, line: 95.4, method: 91.5

        expect(config.minimum_coverage).to eq branch: 85.0, line: 95.4, method: 91.5
      end

      it "raises when trying to set branch coverage but not enabled" do
        expect do
          config.public_send(coverage_setting, {branch: 42})
        end.to raise_error(/branch.*disabled/i)
      end

      it "raises when unknown coverage criteria provided" do
        expect do
          config.public_send(coverage_setting, {unknown: 42})
        end.to raise_error(/unsupported.*unknown/i)
      end

      context "when primary coverage is set" do
        before(:each) do
          config.enable_coverage :branch
          config.primary_coverage :branch
        end

        it "sets the right coverage value when called with a number" do
          config.public_send(coverage_setting, 80)

          expect(config.public_send(coverage_setting)).to eq branch: 80
        end
      end
    end

    describe "#minimum_coverage" do
      it_behaves_like "setting coverage expectations", :minimum_coverage
    end

    describe "#minimum_coverage_by_file" do
      it_behaves_like "setting coverage expectations", :minimum_coverage_by_file
    end

    describe "#maximum_coverage_drop" do
      it_behaves_like "setting coverage expectations", :maximum_coverage_drop
    end

    describe "#refuse_coverage_drop" do
      after :each do
        config.clear_coverage_criteria
      end

      it "sets the right coverage value when called with `:line`" do
        config.public_send(:refuse_coverage_drop, :line)

        expect(config.public_send(:maximum_coverage_drop)).to eq line: 0
      end

      it "sets the right coverage value when called with `:branch`" do
        config.enable_coverage :branch
        config.public_send(:refuse_coverage_drop, :branch)

        expect(config.public_send(:maximum_coverage_drop)).to eq branch: 0
      end

      it "sets the right coverage value when called with `:line` and `:branch`" do
        config.enable_coverage :branch
        config.public_send(:refuse_coverage_drop, :line, :branch)

        expect(config.public_send(:maximum_coverage_drop)).to eq line: 0, branch: 0
      end

      it "sets the right coverage value when called with no args" do
        config.public_send(:refuse_coverage_drop)

        expect(config.public_send(:maximum_coverage_drop)).to eq line: 0
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

      it "works fine with :method" do
        config.coverage_criterion :method

        expect(config.coverage_criterion).to eq :method
      end

      it "works fine setting it back and forth" do
        config.coverage_criterion :branch
        config.coverage_criterion :line

        expect(config.coverage_criterion).to eq :line
      end

      it "errors out on unknown coverage" do
        expect do
          config.coverage_criterion :unknown
        end.to raise_error(/unsupported.*unknown.*line/i)
      end
    end

    describe "#coverage_criteria" do
      it "defaults to line" do
        expect(config.coverage_criteria).to contain_exactly :line
      end
    end

    describe "#enable_coverage" do
      it "can enable branch coverage" do
        config.enable_coverage :branch

        expect(config.coverage_criteria).to contain_exactly :line, :branch
      end

      it "can enable line again" do
        config.enable_coverage :line

        expect(config.coverage_criteria).to contain_exactly :line
      end

      it "can't enable arbitrary things" do
        expect do
          config.enable_coverage :unknown
        end.to raise_error(/unsupported.*unknown.*line/i)
      end
    end

    describe "#branch_coverage?", if: SimpleCov.branch_coverage_supported? do
      it "returns true of branch coverage is being measured" do
        config.enable_coverage :branch

        expect(config).to be_branch_coverage
      end

      it "returns false for line coverage" do
        config.coverage_criterion :line

        expect(config).not_to be_branch_coverage
      end
    end

    describe "#method_coverage?", if: SimpleCov.method_coverage_supported? do
      it "returns true of method coverage is being measured" do
        config.enable_coverage :method

        expect(config).to be_method_coverage
      end

      it "returns false for line coverage" do
        config.coverage_criterion :line

        expect(config).not_to be_method_coverage
      end
    end

    describe "#enable_for_subprocesses" do
      it "returns false by default" do
        expect(config.enable_for_subprocesses).to eq false
      end

      it "can be set to true" do
        config.enable_for_subprocesses true

        expect(config.enable_for_subprocesses).to eq true
      end

      it "can be enabled and then disabled again" do
        config.enable_for_subprocesses true
        config.enable_for_subprocesses false

        expect(config.enable_for_subprocesses).to eq false
      end
    end

    describe "#primary_coverage" do
      context "when branch coverage is enabled" do
        before(:each) { config.enable_coverage :branch }

        it "can set primary coverage to branch" do
          config.primary_coverage :branch

          expect(config.coverage_criteria).to contain_exactly :line, :branch
          expect(config.primary_coverage).to eq :branch
        end
      end

      context "when branch coverage is not enabled" do
        it "cannot set primary coverage to branch " do
          expect do
            config.primary_coverage :branch
          end.to raise_error(/branch.*disabled/i)
        end
      end

      it "can set primary coverage to line" do
        config.primary_coverage :line

        expect(config.coverage_criteria).to contain_exactly :line
        expect(config.primary_coverage).to eq :line
      end

      it "can't set primary coverage to arbitrary things" do
        expect do
          config.primary_coverage :unknown
        end.to raise_error(/unsupported.*unknown.*line/i)
      end
    end
  end
end
