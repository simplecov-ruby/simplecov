# frozen_string_literal: true

require "helper"
require "coverage"

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

  describe "#project_name" do
    it "uses the basename of the configured root, capitalized" do
      config.root("/Users/erik/Code/my_app")
      expect(config.project_name).to eq("My app")
    end

    it "does not raise when root is the filesystem root" do
      config.root("/")
      expect { config.project_name }.not_to raise_error
    end
  end

  describe "#nocov_token" do
    it "warns of deprecation when called as a getter" do
      stderr = capture_stderr { config.nocov_token }

      expect(stderr).to include("[DEPRECATION]")
      expect(stderr).to include("`SimpleCov.nocov_token`")
      expect(stderr).to include("`# simplecov:disable`")
      expect(stderr).to include("`# simplecov:enable`")
    end

    it "warns of deprecation when called as a setter" do
      stderr = capture_stderr { config.nocov_token("skippit") }

      expect(stderr).to include("[DEPRECATION]")
    end

    it "still returns the configured token (after the deprecation warning)" do
      capture_stderr { config.nocov_token("skippit") }
      value = nil
      stderr = capture_stderr { value = config.nocov_token }

      expect(value).to eq "skippit"
      expect(stderr).to include("[DEPRECATION]") # the read still warns
    end

    it "is aliased as #skip_token, which also warns" do
      stderr = capture_stderr { config.skip_token("skippit") }

      expect(stderr).to include("[DEPRECATION]")
      expect(config.current_nocov_token).to eq "skippit"
    end
  end

  describe "#current_nocov_token" do
    it "returns the configured token without emitting a deprecation warning" do
      value = nil
      stderr = capture_stderr { value = config.current_nocov_token }

      expect(value).to eq "nocov"
      expect(stderr).to be_empty
    end

    it "honours a value previously set via #nocov_token" do
      capture_stderr { config.nocov_token("skippit") }

      expect(config.current_nocov_token).to eq "skippit"
    end
  end

  describe "#tracked_files" do
    context "when configured" do
      let(:glob) { "{app,lib}/**/*.rb" }

      before { config.track_files(glob) }

      it "returns the configured glob" do
        expect(config.tracked_files).to eq glob
      end

      context "when configured again with nil" do
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
      after do
        config.clear_coverage_criteria
      end

      it "does not warn you about your usage" do
        allow(config).to receive(:warn)
        config.public_send(coverage_setting, 100.00)
        expect(config).not_to have_received(:warn)
      end

      it "warns you about your usage" do
        allow(config).to receive(:warn)
        config.public_send(coverage_setting, 100.01)
        expect(config).to have_received(:warn).with("The coverage you set for #{coverage_setting} is greater than 100%")
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
        before do
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

    describe "#minimum_coverage_by_group" do
      after do
        config.clear_coverage_criteria
      end

      it "does not warn you about your usage" do
        allow(config).to receive(:warn)
        config.minimum_coverage_by_group({"Test Group 1" => 100.00})
        expect(config).not_to have_received(:warn)
      end

      it "warns you about your usage" do
        allow(config).to receive(:warn)
        config.minimum_coverage_by_group({"Test Group 1" => 100.01})
        expect(config).to have_received(:warn)
          .with("The coverage you set for minimum_coverage_by_group is greater than 100%")
      end

      it "sets the right coverage value when called with a number" do
        config.minimum_coverage_by_group({"Test Group 1" => 80})

        expect(config.minimum_coverage_by_group).to eq({"Test Group 1" => {line: 80}})
      end

      it "sets the right coverage when called with a hash of just line" do
        config.minimum_coverage_by_group({"Test Group 1" => {line: 85.0}})

        expect(config.minimum_coverage_by_group).to eq({"Test Group 1" => {line: 85.0}})
      end

      it "sets the right coverage when called with a hash of just branch" do
        config.enable_coverage :branch
        config.minimum_coverage_by_group({"Test Group 1" => {branch: 85.0}})

        expect(config.minimum_coverage_by_group).to eq({"Test Group 1" => {branch: 85.0}})
      end

      it "sets the right coverage when called with both line and branch" do
        config.enable_coverage :branch
        config.minimum_coverage_by_group({"Test Group 1" => {branch: 85.0, line: 95.4}})

        expect(config.minimum_coverage_by_group).to eq({"Test Group 1" => {branch: 85.0, line: 95.4}})
      end

      it "raises when trying to set branch coverage but not enabled" do
        expect do
          config.minimum_coverage_by_group({"Test Group 1" => {branch: 42}})
        end.to raise_error(/branch.*disabled/i)
      end

      it "raises when unknown coverage criteria provided" do
        expect do
          config.minimum_coverage_by_group({"Test Group 1" => {unknown: 42}})
        end.to raise_error(/unsupported.*unknown/i)
      end

      context "when primary coverage is set" do
        before do
          config.enable_coverage :branch
          config.primary_coverage :branch
        end

        it "sets the right coverage value when called with a number" do
          config.minimum_coverage_by_group({"Test Group 1" => 80})

          expect(config.minimum_coverage_by_group).to eq({"Test Group 1" => {branch: 80}})
        end
      end
    end

    describe "#maximum_coverage_drop" do
      it_behaves_like "setting coverage expectations", :maximum_coverage_drop
    end

    describe "#refuse_coverage_drop" do
      after do
        config.clear_coverage_criteria
      end

      it "sets the right coverage value when called with `:line`" do
        config.refuse_coverage_drop(:line)

        expect(config.maximum_coverage_drop).to eq line: 0
      end

      it "sets the right coverage value when called with `:branch`" do
        config.enable_coverage :branch
        config.refuse_coverage_drop(:branch)

        expect(config.maximum_coverage_drop).to eq branch: 0
      end

      it "sets the right coverage value when called with `:line` and `:branch`" do
        config.enable_coverage :branch
        config.refuse_coverage_drop(:line, :branch)

        expect(config.maximum_coverage_drop).to eq line: 0, branch: 0
      end

      it "sets the right coverage value when called with no args" do
        config.refuse_coverage_drop

        expect(config.maximum_coverage_drop).to eq line: 0
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
      it "returns true if method coverage is being measured" do
        config.enable_coverage :method

        expect(config).to be_method_coverage
      end

      it "returns false for line coverage" do
        config.coverage_criterion :line

        expect(config).not_to be_method_coverage
      end
    end

    describe "#enable_coverage with :method" do
      it "can enable method coverage" do
        config.enable_coverage :method

        expect(config.coverage_criteria).to contain_exactly :line, :method
      end
    end

    describe "#coverage_criterion with :method" do
      it "works fine with :method" do
        config.coverage_criterion :method

        expect(config.coverage_criterion).to eq :method
      end
    end

    describe "#enable_for_subprocesses" do
      it "returns false by default" do
        expect(config.enable_for_subprocesses).to be false
      end

      it "can be set to true" do
        config.enable_for_subprocesses true

        expect(config.enable_for_subprocesses).to be true
      end

      it "can be enabled and then disabled again" do
        config.enable_for_subprocesses true
        config.enable_for_subprocesses false

        expect(config.enable_for_subprocesses).to be false
      end
    end

    describe "#coverage_for_eval_enabled?" do
      it "is false by default" do
        expect(config.coverage_for_eval_enabled?).to be false
      end
    end

    describe "#formatter" do
      it "raises when assigned a falsey value" do
        # `formatter(nil)` is a getter on a defined @formatter; pass a
        # falsey arg directly to take the assignment branch.
        expect { config.formatter(false) }.to raise_error(/No formatter configured/)
      end
    end

    describe "#formatters" do
      after do
        config.instance_variable_set(:@formatter, SimpleCov::Formatter::HTMLFormatter)
      end

      it "wraps a single formatter as an Array" do
        config.formatter = SimpleCov::Formatter::SimpleFormatter
        expect(config.formatters).to eq([SimpleCov::Formatter::SimpleFormatter])
      end
    end

    describe "#at_exit" do
      around do |example|
        previous = config.instance_variable_get(:@at_exit)
        config.instance_variable_set(:@at_exit, nil)
        example.run
        config.instance_variable_set(:@at_exit, previous)
      end

      it "returns a default proc (formats the result) when called with no block while Coverage is running" do
        allow(Coverage).to receive(:running?).and_return(true)
        proc_returned = config.at_exit
        expect(proc_returned).to be_a(Proc)
      end

      it "remembers an explicit block across calls" do
        explicit = proc {}
        config.at_exit(&explicit)
        expect(config.at_exit).to equal(explicit)
      end

      it "returns a no-op when no session is active and no block is stored" do
        allow(SimpleCov).to receive_messages(result?: false, result: nil)
        allow(Coverage).to receive(:running?).and_return(false)
        config.at_exit.call
        expect(SimpleCov).not_to have_received(:result)
      end
    end

    describe "#at_fork" do
      around do |example|
        previous = SimpleCov.instance_variable_get(:@at_fork)
        SimpleCov.instance_variable_set(:@at_fork, nil)
        example.run
        SimpleCov.instance_variable_set(:@at_fork, previous)
      end

      it "remembers an explicit block across calls" do
        explicit = proc { |_pid| }
        SimpleCov.at_fork(&explicit)
        expect(SimpleCov.at_fork).to equal(explicit)
      end

      it "default lambda re-applies subprocess-friendly config" do
        # Stub the global mutations so this spec doesn't trash the rest
        # of the suite's SimpleCov configuration / restart Coverage.
        allow(SimpleCov).to receive(:command_name)
        allow(SimpleCov).to receive(:print_error_status=)
        allow(SimpleCov).to receive(:formatter)
        allow(SimpleCov).to receive(:minimum_coverage)
        allow(SimpleCov).to receive(:start)

        SimpleCov.at_fork.call(12_345)

        expect(SimpleCov).to have_received(:command_name).with(/subprocess: 12345/)
        expect(SimpleCov).to have_received(:print_error_status=).with(false)
        expect(SimpleCov).to have_received(:formatter).with(SimpleCov::Formatter::SimpleFormatter)
        expect(SimpleCov).to have_received(:minimum_coverage).with(0)
        expect(SimpleCov).to have_received(:start)
      end
    end

    describe "#command_name" do
      after { config.instance_variable_set(:@name, nil) }

      it "stores an explicit name" do
        config.command_name("My Suite")
        expect(config.command_name).to eq("My Suite")
      end
    end

    describe "#project_name" do
      after { config.instance_variable_set(:@project_name, nil) }

      it "stores an explicit name" do
        config.project_name("Custom")
        expect(config.project_name).to eq("Custom")
      end
    end

    describe "#merge_timeout" do
      after { config.instance_variable_set(:@merge_timeout, nil) }

      it "stores an explicit integer value" do
        config.merge_timeout(120)
        expect(config.merge_timeout).to eq(120)
      end
    end

    describe "#parse_filter" do
      it "raises when given neither a filter argument nor a block" do
        expect { config.send(:parse_filter) }.to raise_error(ArgumentError, /filter or a block/)
      end
    end

    describe "#configure" do
      it "uses instance_exec directly when the block is in our own context" do
        # Stub equal? so the "block defined in our own context" branch fires
        # without contorting the test to share a binding with the config.
        allow(config).to receive(:equal?).and_return(true)
        config.configure { @configured = true }
        expect(config.instance_variable_get(:@configured)).to be true
      end
    end

    describe "#use_merging" do
      around do |example|
        previous = config.instance_variable_get(:@use_merging)
        config.instance_variable_set(:@use_merging, nil)
        example.run
        config.instance_variable_set(:@use_merging, previous)
      end

      it "stores the explicit value when given true" do
        config.use_merging(true)
        expect(config.instance_variable_get(:@use_merging)).to be true
      end

      it "stores the explicit value when given false" do
        config.use_merging(false)
        expect(config.instance_variable_get(:@use_merging)).to be false
      end

      it "defaults to true when never set" do
        expect(config.use_merging).to be true
      end
    end

    describe "#enable_coverage_for_eval" do
      context "when the runtime supports eval coverage" do
        before { allow(config).to receive(:coverage_for_eval_supported?).and_return(true) }

        it "flips coverage_for_eval_enabled? to true" do
          config.enable_coverage_for_eval

          expect(config.coverage_for_eval_enabled?).to be true
        end
      end

      context "when the runtime does not support eval coverage" do
        before { allow(config).to receive(:coverage_for_eval_supported?).and_return(false) }

        it "leaves the flag false and warns" do
          stderr = capture_stderr { config.enable_coverage_for_eval }

          expect(config.coverage_for_eval_enabled?).to be false
          expect(stderr).to include("Coverage for eval is not available")
        end
      end
    end

    describe "#primary_coverage" do
      context "when branch coverage is enabled" do
        before { config.enable_coverage :branch }

        it "can set primary coverage to branch" do
          config.primary_coverage :branch

          expect(config.coverage_criteria).to contain_exactly :line, :branch
          expect(config.primary_coverage).to eq :branch
        end
      end

      context "when branch coverage is not enabled" do
        it "cannot set primary coverage to branch" do
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

      it "can set primary coverage to oneshot_line" do
        config.enable_coverage :oneshot_line
        config.primary_coverage :oneshot_line

        expect(config.coverage_criteria).to contain_exactly :oneshot_line
        expect(config.primary_coverage).to eq :oneshot_line
      end

      it "can't set primary coverage to arbitrary things" do
        expect do
          config.primary_coverage :unknown
        end.to raise_error(/unsupported.*unknown.*line/i)
      end
    end
  end
end
