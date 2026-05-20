# frozen_string_literal: true

require "helper"
require "coverage"

RSpec.describe SimpleCov do
  describe ".install_at_exit_hook" do
    around do |example|
      previous_installed = described_class.instance_variable_get(:@at_exit_hook_installed)
      previous_external  = described_class.external_at_exit
      described_class.instance_variable_set(:@at_exit_hook_installed, nil)
      example.run
      described_class.instance_variable_set(:@at_exit_hook_installed, previous_installed)
      described_class.external_at_exit = previous_external
    end

    it "is idempotent — repeated calls register exactly one Kernel.at_exit" do
      allow(Kernel).to receive(:at_exit)
      described_class.install_at_exit_hook
      described_class.install_at_exit_hook
      expect(Kernel).to have_received(:at_exit).once
    end

    it "registers a block that runs at_exit_behavior unless external_at_exit? is set" do
      captured = nil
      allow(Kernel).to receive(:at_exit) { |&blk| captured = blk }
      described_class.install_at_exit_hook

      allow(described_class).to receive(:external_at_exit?).and_return(false)
      allow(described_class).to receive(:at_exit_behavior)
      captured.call
      expect(described_class).to have_received(:at_exit_behavior)
    end

    it "registers a block that bails out when external_at_exit? is set" do
      captured = nil
      allow(Kernel).to receive(:at_exit) { |&blk| captured = blk }
      described_class.install_at_exit_hook

      allow(described_class).to receive(:external_at_exit?).and_return(true)
      allow(described_class).to receive(:at_exit_behavior)
      captured.call
      expect(described_class).not_to have_received(:at_exit_behavior)
    end

    context "when Minitest's autorun is armed before SimpleCov.start" do
      # Stand-in for Minitest with the same surface we depend on:
      # responds to `after_run` and exposes the `@@installed_at_exit`
      # class variable that Minitest sets when autorun is required.
      let(:fake_minitest) do
        klass = Class.new do
          class << self
            attr_reader :after_run_blocks
          end
          @after_run_blocks = []
          def self.after_run(&block)
            @after_run_blocks << block
          end
        end
        klass.class_variable_set(:@@installed_at_exit, true) # rubocop:disable Style/ClassVars
        klass
      end

      before { stub_const("Minitest", fake_minitest) }

      it "sets external_at_exit and registers Minitest.after_run" do
        allow(Kernel).to receive(:at_exit)
        described_class.install_at_exit_hook

        expect(described_class.external_at_exit?).to be(true)
        expect(fake_minitest.after_run_blocks.size).to eq(1)
      end

      it "the after_run block invokes at_exit_behavior" do
        allow(Kernel).to receive(:at_exit)
        allow(described_class).to receive(:at_exit_behavior)
        described_class.install_at_exit_hook

        fake_minitest.after_run_blocks.each(&:call)
        expect(described_class).to have_received(:at_exit_behavior)
      end
    end

    it "does not defer to Minitest when it is loaded but autorun has not been called" do
      fake_minitest = Class.new { def self.after_run; end }
      fake_minitest.class_variable_set(:@@installed_at_exit, false) # rubocop:disable Style/ClassVars
      stub_const("Minitest", fake_minitest)
      allow(Kernel).to receive(:at_exit)
      allow(fake_minitest).to receive(:after_run)

      described_class.install_at_exit_hook

      expect(described_class).not_to be_external_at_exit
      expect(fake_minitest).not_to have_received(:after_run)
    end

    it "does not defer when a Minitest-like constant lacks @@installed_at_exit" do
      fake_minitest = Class.new { def self.after_run; end }
      stub_const("Minitest", fake_minitest)
      allow(Kernel).to receive(:at_exit)
      allow(fake_minitest).to receive(:after_run)

      described_class.install_at_exit_hook

      expect(described_class).not_to be_external_at_exit
      expect(fake_minitest).not_to have_received(:after_run)
    end
  end

  describe ".start" do
    it "delegates to initial_setup, start_tracking, and install_at_exit_hook" do
      # Stub the three pieces so this spec doesn't actually load a
      # profile, mutate global filter state, or restart Coverage.
      allow(described_class).to receive(:send).and_call_original
      allow(described_class).to receive(:initial_setup)
      allow(described_class).to receive(:start_tracking)
      allow(described_class).to receive(:install_at_exit_hook)
      block = proc {}

      described_class.start("rails", &block)

      expect(described_class).to have_received(:initial_setup)
      expect(described_class).to have_received(:start_tracking)
      expect(described_class).to have_received(:install_at_exit_hook)
    end

    # See issue #581 for the rationale: `.simplecov` should be config only.
    # The autoload wrapper sets this flag so any legacy `SimpleCov.start`
    # call inside the file warns and applies configuration without starting
    # Coverage.
    context "when loaded by the .simplecov autoloader" do
      around do |example|
        previous = described_class.instance_variable_get(:@autoloading_dot_simplecov)
        warned = described_class.instance_variable_get(:@dot_simplecov_start_warned)
        described_class.instance_variable_set(:@dot_simplecov_start_warned, nil)
        described_class.with_dot_simplecov_autoload { example.run }
        described_class.instance_variable_set(:@autoloading_dot_simplecov, previous)
        described_class.instance_variable_set(:@dot_simplecov_start_warned, warned)
      end

      it "still applies configuration AND starts tracking (soft deprecation for backward compatibility)" do
        # The deprecation is advisory: existing setups keep working while
        # the warning nudges users toward moving `SimpleCov.start` into a
        # test helper. A future release will tighten this into a hard
        # intercept. See issue #581.
        allow(described_class).to receive_messages(initial_setup: nil, start_tracking: nil,
                                                   install_at_exit_hook: nil)
        allow(described_class).to receive(:warn) # suppress deprecation noise in test output
        block = proc {}

        described_class.start("rails", &block)

        expect(described_class).to have_received(:initial_setup)
        expect(described_class).to have_received(:start_tracking)
        expect(described_class).to have_received(:install_at_exit_hook)
      end

      it "emits a one-time deprecation warning pointing at the migration path" do
        allow(described_class).to receive_messages(initial_setup: nil, start_tracking: nil,
                                                   install_at_exit_hook: nil)
        stderr = capture_stderr { described_class.start }
        expect(stderr).to include("[DEPRECATION]")
        expect(stderr).to include("`.simplecov`")
        expect(stderr).to include("spec_helper.rb")
        expect(stderr).to include("581")
      end

      it "doesn't repeat the warning on subsequent calls" do
        allow(described_class).to receive_messages(initial_setup: nil, start_tracking: nil,
                                                   install_at_exit_hook: nil)
        first  = capture_stderr { described_class.start }
        second = capture_stderr { described_class.start }
        expect(first).to include("[DEPRECATION]")
        expect(second).to be_empty
      end
    end
  end

  describe ".with_dot_simplecov_autoload" do
    it "sets the flag during the block and restores it after" do
      described_class.instance_variable_set(:@autoloading_dot_simplecov, false)
      observed = nil
      described_class.with_dot_simplecov_autoload do
        observed = described_class.instance_variable_get(:@autoloading_dot_simplecov)
      end
      expect(observed).to be(true)
      expect(described_class.instance_variable_get(:@autoloading_dot_simplecov)).to be(false)
    end

    it "restores the flag even when the block raises" do
      described_class.instance_variable_set(:@autoloading_dot_simplecov, false)
      expect { described_class.with_dot_simplecov_autoload { raise "boom" } }.to raise_error("boom")
      expect(described_class.instance_variable_get(:@autoloading_dot_simplecov)).to be(false)
    end
  end

  describe ".initial_setup" do
    it "loads the profile when given" do
      allow(described_class).to receive_messages(load_profile: nil, configure: nil)
      described_class.send(:initial_setup, "rails")
      expect(described_class).to have_received(:load_profile).with("rails")
    end

    it "calls configure when a block is given" do
      allow(described_class).to receive(:configure)
      described_class.send(:initial_setup, nil, &proc {})
      expect(described_class).to have_received(:configure)
    end
  end

  describe ".start_coverage_with_criteria" do
    it "passes eval: true to Coverage.start when coverage_for_eval is enabled" do
      allow(Coverage).to receive_messages(running?: false)
      allow(Coverage).to receive(:start)
      allow(described_class).to receive(:coverage_for_eval_enabled?).and_return(true)
      described_class.send(:start_coverage_with_criteria)
      expect(Coverage).to have_received(:start).with(hash_including(eval: true))
    end

    it "omits `lines: true` when :line coverage has been disabled" do
      skip "branch coverage not supported on this engine" unless described_class.branch_coverage_supported?

      allow(Coverage).to receive_messages(running?: false)
      allow(Coverage).to receive(:start)
      previous = described_class.coverage_criteria.dup
      described_class.enable_coverage :branch
      described_class.disable_coverage :line
      described_class.send(:start_coverage_with_criteria)
      expect(Coverage).to have_received(:start).with(branches: true)
    ensure
      described_class.clear_coverage_criteria
      previous&.each { |c| described_class.enable_coverage(c) }
    end
  end

  describe ".start_tracking with all criteria disabled" do
    it "raises a ConfigurationError" do
      previous = described_class.coverage_criteria.dup
      previous.each { |c| described_class.disable_coverage(c) }
      expect { described_class.validate_coverage_criteria! }
        .to raise_error(SimpleCov::ConfigurationError, /At least one coverage criterion/)
    ensure
      previous.each { |c| described_class.enable_coverage(c) }
    end
  end

  describe ".add_not_loaded_files" do
    around do |example|
      previous = described_class.tracked_files
      example.run
      described_class.track_files(previous)
    end

    it "returns the input unchanged when no track_files glob is configured" do
      described_class.track_files(nil)
      result = {"/abs/foo.rb" => {"lines" => [1]}}
      expect(described_class.send(:add_not_loaded_files, result)).to eq([result, Set.new])
    end

    it "augments the result with files matched by the glob that weren't loaded" do
      described_class.track_files("spec/fixtures/sample.rb")
      sample = File.expand_path("spec/fixtures/sample.rb", described_class.root)
      result, not_loaded = described_class.send(:add_not_loaded_files, {})
      expect(not_loaded).to include(sample)
      expect(result).to have_key(sample)
    end

    it "skips files that are already present in the input result" do
      described_class.track_files("spec/fixtures/sample.rb")
      sample = File.expand_path("spec/fixtures/sample.rb", described_class.root)
      preloaded = {sample => {"lines" => [1]}}
      result, not_loaded = described_class.send(:add_not_loaded_files, preloaded)
      expect(not_loaded).not_to include(sample)
      expect(result[sample]).to eq("lines" => [1])
    end

    # The track_files glob has to be project-root-relative, not cwd-
    # relative — test runners that chdir would otherwise silently miss
    # unloaded files and emit different file sets per environment. See #1106.
    it "resolves the glob relative to SimpleCov.root regardless of cwd" do
      described_class.track_files("spec/fixtures/sample.rb")
      sample = File.expand_path(File.join(described_class.root, "spec/fixtures/sample.rb"))
      Dir.chdir(Dir.tmpdir) do
        _result, not_loaded = described_class.send(:add_not_loaded_files, {})
        expect(not_loaded).to include(sample)
      end
    end
  end

  describe ".ready_to_process_results?" do
    it "is true when both final_result_process? and result? are truthy" do
      allow(described_class).to receive_messages(final_result_process?: true, result?: true)
      expect(described_class.ready_to_process_results?).to be true
    end

    it "is false when final_result_process? is false" do
      allow(described_class).to receive(:final_result_process?).and_return(false)
      expect(described_class.ready_to_process_results?).to be false
    end
  end

  describe ".final_result_process?" do
    it "is true when ParallelTests isn't loaded" do
      expect(described_class.send(:final_result_process?)).to be_truthy
    end

    context "when running under a faked parallel_tests setup" do
      # `Class.new { def self.last_process?; end }` rather than a plain
      # Class.new so rspec-mocks 4's verify_partial_doubles check (now
      # on by default) accepts the subsequent `allow(...).to receive(
      # :last_process?)` stubs.
      before { stub_const("ParallelTests", Class.new { def self.last_process?; end }) }

      around do |example|
        prev_n, prev_g = ENV.values_at("TEST_ENV_NUMBER", "PARALLEL_TEST_GROUPS")
        example.run
      ensure
        ENV["TEST_ENV_NUMBER"] = prev_n
        ENV["PARALLEL_TEST_GROUPS"] = prev_g
      end

      # parallel_tests sets the first worker's TEST_ENV_NUMBER to "" and
      # last_process? compares it against PARALLEL_TEST_GROUPS as a string,
      # so "" == "1" is false. Without compensating, a `parallel:spec[1]`
      # run silently skipped minimum_coverage enforcement (#1066).
      it "is true when running with PARALLEL_TEST_GROUPS=1" do
        ENV["TEST_ENV_NUMBER"] = ""
        ENV["PARALLEL_TEST_GROUPS"] = "1"
        allow(ParallelTests).to receive(:last_process?).and_return(false)
        expect(described_class.send(:final_result_process?)).to be true
      end

      it "is false for a non-last worker in a multi-group run" do
        ENV["TEST_ENV_NUMBER"] = ""
        ENV["PARALLEL_TEST_GROUPS"] = "2"
        allow(ParallelTests).to receive(:last_process?).and_return(false)
        expect(described_class.send(:final_result_process?)).to be false
      end

      it "is true for the last worker in a multi-group run" do
        ENV["TEST_ENV_NUMBER"] = "2"
        ENV["PARALLEL_TEST_GROUPS"] = "2"
        allow(ParallelTests).to receive(:last_process?).and_return(true)
        expect(described_class.send(:final_result_process?)).to be true
      end
    end
  end

  describe ".wait_for_other_processes" do
    it "returns early when ParallelTests is not loaded" do
      expect(described_class.send(:wait_for_other_processes)).to be_nil
    end
  end

  describe ".wait_for_parallel_results" do
    it "returns early when PARALLEL_TEST_GROUPS is unset" do
      ENV.delete("PARALLEL_TEST_GROUPS")
      expect(described_class.send(:wait_for_parallel_results)).to be_nil
    end

    it "returns early for a single-group parallel run" do
      ENV["PARALLEL_TEST_GROUPS"] = "1"
      expect(described_class.send(:wait_for_parallel_results)).to be_nil
    ensure
      ENV.delete("PARALLEL_TEST_GROUPS")
    end
  end

  describe ".at_exit_behavior" do
    around do |example|
      previous_pid = described_class.pid
      example.run
      described_class.pid = previous_pid
    end

    it "is a no-op when called from a different process than start" do
      described_class.pid = -1 # never matches Process.pid
      allow(described_class).to receive(:run_exit_tasks!)
      described_class.at_exit_behavior
      expect(described_class).not_to have_received(:run_exit_tasks!)
    end

    it "runs exit tasks when in the same process and Coverage is running" do
      described_class.pid = Process.pid
      allow(Coverage).to receive(:running?).and_return(true)
      allow(described_class).to receive(:defer_to_existing_report?).and_return(false)
      allow(described_class).to receive(:run_exit_tasks!)
      described_class.at_exit_behavior
      expect(described_class).to have_received(:run_exit_tasks!)
    end

    it "skips exit tasks when Coverage has stopped" do
      described_class.pid = Process.pid
      allow(Coverage).to receive(:running?).and_return(false)
      allow(described_class).to receive(:run_exit_tasks!)
      described_class.at_exit_behavior
      expect(described_class).not_to have_received(:run_exit_tasks!)
    end

    it "defers to the existing on-disk report when our result is empty and the disk report is fresher" do
      described_class.pid = Process.pid
      allow(Coverage).to receive(:running?).and_return(true)
      allow(described_class).to receive(:defer_to_existing_report?).and_return(true)
      allow(described_class).to receive(:run_exit_tasks!)
      described_class.at_exit_behavior
      expect(described_class).not_to have_received(:run_exit_tasks!)
    end
  end

  describe ".defer_to_existing_report?" do
    let(:tmp) { Dir.mktmpdir }
    let(:last_run_path) { File.join(tmp, ".last_run.json") }

    before { allow(described_class).to receive(:coverage_path).and_return(tmp) }
    after { FileUtils.remove_entry(tmp) }

    it "is false when process_start_time is unset" do
      allow(described_class).to receive(:process_start_time).and_return(nil)
      expect(described_class.defer_to_existing_report?).to be false
    end

    it "is false when no on-disk last_run report exists" do
      allow(described_class).to receive(:process_start_time).and_return(Time.now)
      expect(described_class.defer_to_existing_report?).to be false
    end

    it "is false when the on-disk report predates this process" do
      File.write(last_run_path, "{}")
      old = File.mtime(last_run_path) - 60
      allow(described_class).to receive(:process_start_time).and_return(Time.now)
      File.utime(old, old, last_run_path)
      expect(described_class.defer_to_existing_report?).to be false
    end

    context "when on-disk report is newer than this process" do
      before do
        File.write(last_run_path, "{}")
        future = Time.now + 60
        File.utime(future, future, last_run_path)
        allow(described_class).to receive(:process_start_time).and_return(Time.now)
      end

      it "is false when our merged result still has files (we have something to contribute)" do
        result = instance_double(SimpleCov::Result, files: [:some_file])
        allow(described_class).to receive(:result).and_return(result)
        expect(described_class.defer_to_existing_report?).to be false
      end

      it "is true when our merged result is empty (we'd clobber a better report)" do
        result = instance_double(SimpleCov::Result, files: [])
        allow(described_class).to receive(:result).and_return(result)
        allow(described_class).to receive(:warn_about_deferred_report)
        expect(described_class.defer_to_existing_report?).to be true
      end

      it "warns about the deferral once when triggered" do
        result = instance_double(SimpleCov::Result, files: [])
        allow(described_class).to receive_messages(result: result, print_error_status: true)
        stderr = capture_stderr { described_class.defer_to_existing_report? }
        expect(stderr).to include("Skipping SimpleCov report")
        expect(stderr).to include("581")
      end

      it "still defers but stays silent when print_error_status is false" do
        result = instance_double(SimpleCov::Result, files: [])
        allow(described_class).to receive_messages(result: result, print_error_status: false)
        stderr = capture_stderr do
          expect(described_class.defer_to_existing_report?).to be true
        end
        expect(stderr).to be_empty
      end
    end
  end

  describe ".run_exit_tasks!" do
    it "calls at_exit, then handles previous-error and result-processing branches" do
      proc_double = proc {}
      allow(described_class).to receive(:exit_and_report_previous_error)
      allow(described_class).to receive_messages(exit_status_from_exception: 1, at_exit: proc_double,
                                                 previous_error?: true, ready_to_process_results?: false)

      described_class.run_exit_tasks!

      expect(described_class).to have_received(:exit_and_report_previous_error).with(1)
    end

    it "calls process_results_and_report_error when ready and no previous error" do
      proc_double = proc {}
      allow(described_class).to receive_messages(exit_status_from_exception: nil, at_exit: proc_double,
                                                 previous_error?: false, ready_to_process_results?: true)
      allow(described_class).to receive(:process_results_and_report_error)

      described_class.run_exit_tasks!

      expect(described_class).to have_received(:process_results_and_report_error)
    end
  end

  describe ".previous_error?" do
    it "is truthy for a non-success exit status" do
      expect(described_class).to be_previous_error(SimpleCov::ExitCodes::MINIMUM_COVERAGE)
    end

    it "is falsey for SUCCESS" do
      expect(described_class).not_to be_previous_error(SimpleCov::ExitCodes::SUCCESS)
    end

    it "is falsey for nil" do
      expect(described_class).not_to be_previous_error(nil)
    end
  end

  describe ".exit_and_report_previous_error" do
    it "warns when print_error_status is true and exits with the given status" do
      allow(described_class).to receive(:print_error_status).and_return(true)
      allow(Kernel).to receive(:exit)
      stderr = capture_stderr { described_class.exit_and_report_previous_error(2) }
      expect(stderr).to include("Stopped processing SimpleCov")
      expect(Kernel).to have_received(:exit).with(2)
    end

    it "is silent when print_error_status is false" do
      allow(described_class).to receive(:print_error_status).and_return(false)
      allow(Kernel).to receive(:exit)
      stderr = capture_stderr { described_class.exit_and_report_previous_error(2) }
      expect(stderr).to be_empty
    end
  end

  describe ".process_results_and_report_error" do
    it "exits with the coverage-related error status when process_result returns positive" do
      allow(described_class).to receive_messages(result: double, process_result: 2, print_error_status: true)
      allow(Kernel).to receive(:exit)

      stderr = capture_stderr { described_class.process_results_and_report_error }

      expect(stderr).to include("SimpleCov failed with exit 2")
      expect(Kernel).to have_received(:exit).with(2)
    end

    it "is a no-op when process_result returns zero" do
      allow(described_class).to receive_messages(result: double, process_result: 0)
      allow(Kernel).to receive(:exit)
      described_class.process_results_and_report_error
      expect(Kernel).not_to have_received(:exit)
    end

    it "stays silent when print_error_status is false but still exits" do
      allow(described_class).to receive_messages(result: double, process_result: 2, print_error_status: false)
      allow(Kernel).to receive(:exit)
      stderr = capture_stderr { described_class.process_results_and_report_error }
      expect(stderr).to be_empty
      expect(Kernel).to have_received(:exit).with(2)
    end
  end

  describe ".grouped" do
    let(:files) do
      [
        instance_double(SimpleCov::SourceFile, filename: "/abs/lib/foo.rb", project_filename: "lib/foo.rb"),
        instance_double(SimpleCov::SourceFile, filename: "/abs/test/foo.rb", project_filename: "test/foo.rb")
      ]
    end

    around do |example|
      previous = described_class.groups
      described_class.groups = {}
      example.run
      described_class.groups = previous
    end

    it "returns {} when no groups are configured" do
      expect(described_class.grouped(files)).to eq({})
    end

    it "buckets files into matching groups and collects unmatched into Ungrouped" do
      described_class.add_group("Lib", "lib")
      result = described_class.grouped(files)
      expect(result.keys).to contain_exactly("Lib", "Ungrouped")
      expect(result["Lib"].map(&:project_filename)).to eq(["lib/foo.rb"])
      expect(result["Ungrouped"].map(&:project_filename)).to eq(["test/foo.rb"])
    end

    it "skips Ungrouped when every file matches a group" do
      described_class.add_group("All", //)
      result = described_class.grouped(files)
      expect(result.keys).to contain_exactly("All")
    end
  end

  describe ".result" do
    before do
      described_class.clear_result
      allow(Coverage).to receive(:result).once.and_return({})
    end

    context "with merging disabled" do
      before do
        allow(described_class).to receive(:use_merging).once.and_return(false)
        allow(described_class).to receive(:wait_for_other_processes)
      end

      context "when not running" do
        before do
          allow(Coverage).to receive(:running?).and_return(false)
        end

        it "returns nil" do
          expect(described_class.result).to be_nil
        end

        it "does not wait for other processes" do
          described_class.result
          expect(described_class).not_to have_received(:wait_for_other_processes)
        end
      end

      context "when running" do
        before do
          allow(Coverage).to receive(:running?).and_return(true)
        end

        it "uses the result from Coverage" do
          allow(Coverage).to receive(:result).and_return(__FILE__ => [0, 1])
          expect(described_class.result.filenames).to eq [__FILE__]
          expect(Coverage).to have_received(:result).once
        end

        it "adds not-loaded-files" do
          allow(described_class).to receive(:add_not_loaded_files).and_return([{}, Set.new])
          described_class.result
          expect(described_class).to have_received(:add_not_loaded_files).once
        end

        it "doesn't store the current coverage" do
          allow(SimpleCov::ResultMerger).to receive(:store_result)
          described_class.result
          expect(SimpleCov::ResultMerger).not_to have_received(:store_result)
        end

        it "doesn't merge the result" do
          allow(SimpleCov::ResultMerger).to receive(:merged_result)
          described_class.result
          expect(SimpleCov::ResultMerger).not_to have_received(:merged_result)
        end

        it "caches its result" do
          result = described_class.result
          expect(described_class.result).to be(result)
        end

        it "does not wait for other processes" do
          described_class.result
          expect(described_class).not_to have_received(:wait_for_other_processes)
        end
      end
    end

    context "with merging enabled" do
      let(:the_merged_result) { double }

      before do
        allow(described_class).to receive(:use_merging).once.and_return(true)
        allow(SimpleCov::ResultMerger).to receive(:store_result).once
        allow(SimpleCov::ResultMerger).to receive(:merged_result).once.and_return(the_merged_result)
        allow(described_class).to receive(:wait_for_other_processes)
      end

      context "when not running" do
        before do
          allow(Coverage).to receive(:running?).and_return(false)
        end

        it "merges the result" do
          expect(described_class.result).to be(the_merged_result)
        end

        it "waits for other processes" do
          described_class.result
          expect(described_class).to have_received(:wait_for_other_processes)
        end
      end

      context "when running" do
        before do
          allow(Coverage).to receive(:running?).and_return(true)
        end

        it "uses the result from Coverage" do
          allow(Coverage).to receive(:result).and_return({})
          described_class.result
          expect(Coverage).to have_received(:result).once
        end

        it "adds not-loaded-files" do
          allow(described_class).to receive(:add_not_loaded_files).and_return([{}, Set.new])
          described_class.result
          expect(described_class).to have_received(:add_not_loaded_files).once
        end

        it "stores the current coverage" do
          allow(SimpleCov::ResultMerger).to receive(:store_result)
          described_class.result
          expect(SimpleCov::ResultMerger).to have_received(:store_result).once
        end

        it "merges the result" do
          expect(described_class.result).to be(the_merged_result)
        end

        it "caches its result" do
          result = described_class.result
          expect(described_class.result).to be(result)
        end

        it "waits for other processes" do
          described_class.result
          expect(described_class).to have_received(:wait_for_other_processes)
        end
      end
    end

    context "when Coverage was never required" do
      it "doesn't raise NameError" do
        described_class.clear_result
        hide_const("Coverage")
        allow(SimpleCov::ResultMerger).to receive(:merged_result).and_return(nil)
        expect { described_class.result }.not_to raise_error
      end
    end
  end

  describe ".exit_status_from_exception" do
    context "when no exception has occurred" do
      it "returns nil" do
        expect(described_class.exit_status_from_exception).to be_nil
      end
    end

    context "when a SystemExit has occurred" do
      it "returns the SystemExit status" do
        raise SystemExit, 1
      rescue SystemExit
        expect(described_class.exit_status_from_exception).to eq(1)
      end
    end

    context "when a non SystemExit occurs" do
      it "return SimpleCov::ExitCodes::EXCEPTION" do
        raise "no system exit"
      rescue StandardError
        expect(described_class.exit_status_from_exception).to eq(SimpleCov::ExitCodes::EXCEPTION)
      end
    end
  end

  describe ".process_result" do
    let(:result) { SimpleCov::Result.new({}) }

    context "when minimum coverage is 100%" do
      before do
        allow(described_class).to receive_messages(minimum_coverage: {line: 100}, result?: true)
      end

      context "when actual coverage is almost 100%" do
        before do
          line_stats = instance_double(SimpleCov::CoverageStatistics, percent: 100 * 32_847.0 / 32_848)
          allow(result).to receive(:coverage_statistics).and_return(line: line_stats)
        end

        it "return SimpleCov::ExitCodes::MINIMUM_COVERAGE" do
          expect(
            described_class.process_result(result)
          ).to eq(SimpleCov::ExitCodes::MINIMUM_COVERAGE)
        end
      end

      context "when actual coverage is exactly 100%" do
        before do
          line_stats = instance_double(SimpleCov::CoverageStatistics, percent: 100.0)
          allow(result).to receive_messages(
            covered_percent: 100.0,
            coverage_statistics: {line: line_stats},
            covered_percentages: []
          )
          allow(SimpleCov::LastRun).to receive(:read).and_return(nil)
        end

        it "return SimpleCov::ExitCodes::SUCCESS" do
          expect(
            described_class.process_result(result)
          ).to eq(SimpleCov::ExitCodes::SUCCESS)
        end
      end

      context "when branch coverage" do
        before do
          allow(described_class).to receive_messages(minimum_coverage: {branch: 90}, result?: true)
        end

        it "errors out when the coverage is too low" do
          branch_stats = instance_double(SimpleCov::CoverageStatistics, percent: 89.99)
          allow(result).to receive(:coverage_statistics).and_return(branch: branch_stats)

          expect(
            described_class.process_result(result)
          ).to eq(SimpleCov::ExitCodes::MINIMUM_COVERAGE)
        end
      end
    end
  end

  describe ".collate" do
    let(:first_resultset) do
      {source_fixture("sample.rb") => {"lines" => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil]}}
    end

    let(:second_resultset) do
      {source_fixture("sample.rb") => {"lines" => [1, nil, 1, 1, nil, nil, 1, 1, nil, nil]}}
    end

    let(:resultset_path) { SimpleCov::ResultMerger.resultset_path }

    let(:resultset_folder) { File.dirname(resultset_path) }

    let(:merged_result) do
      {
        "result1, result2" => {
          "coverage" => {
            source_fixture("sample.rb") => {
              "lines" => [1, 1, 2, 2, nil, nil, 2, 2, nil, nil]
            }
          }
        }
      }
    end

    let(:collated) do
      JSON.parse(File.read(resultset_path)).transform_values { |v| v.reject { |k| k == "timestamp" } }
    end

    context "when no files to be merged" do
      it "shows an error message" do
        expect do
          glob = Dir.glob("#{resultset_folder}/*.final", File::FNM_DOTMATCH)
          described_class.collate glob
        end.to raise_error("There are no reports to be merged")
      end
    end

    context "when files to be merged" do
      before do
        allow(described_class).to receive(:run_exit_tasks!)
      end

      context "when a single report to be merged" do
        before do
          create_mergeable_report("result1", first_resultset)
        end

        after do
          clear_mergeable_reports
        end

        it "creates a merged report identical to the original" do
          glob = Dir.glob("#{resultset_folder}/*.final", File::FNM_DOTMATCH)
          described_class.collate glob

          expected = {"result1" => {"coverage" => first_resultset}}
          expect(collated).to eq(expected)
          expect(described_class).to have_received(:run_exit_tasks!)
        end
      end

      context "when multiple reports to be merged" do
        before do
          create_mergeable_report("result1", first_resultset)
          create_mergeable_report("result2", second_resultset)
        end

        after do
          clear_mergeable_reports
        end

        it "creates a merged report" do
          glob = Dir.glob("#{resultset_folder}/*.final", File::FNM_DOTMATCH)
          described_class.collate glob

          expect(collated).to eq(merged_result)
          expect(described_class).to have_received(:run_exit_tasks!)
        end
      end

      context "when multiple reports to be merged, one of them outdated" do
        before do
          create_mergeable_report("result1", first_resultset)
          create_mergeable_report("result2", second_resultset, outdated: true)
        end

        after do
          clear_mergeable_reports
        end

        it "ignores timeout by default creating a report with all values" do
          glob = Dir.glob("#{resultset_folder}/*.final", File::FNM_DOTMATCH)
          described_class.collate glob

          expect(collated).to eq(merged_result)
          expect(described_class).to have_received(:run_exit_tasks!)
        end

        it "creates a merged report with only the results from the current resultset if ignore_timeout: false" do
          glob = Dir.glob("#{resultset_folder}/*.final", File::FNM_DOTMATCH)
          described_class.collate glob, ignore_timeout: false

          expected = {"result1" => {"coverage" => first_resultset}}
          expect(collated).to eq(expected)
          expect(described_class).to have_received(:run_exit_tasks!)
        end
      end

    private

      def create_mergeable_report(name, resultset, outdated: false)
        result = SimpleCov::Result.new(resultset)
        result.command_name = name
        result.created_at = Time.now - 172_800 if outdated
        SimpleCov::ResultMerger.store_result(result)
        FileUtils.mv resultset_path, "#{resultset_path}#{name}.final"
      end

      def clear_mergeable_reports
        SimpleCov.clear_result
        FileUtils.rm Dir.glob("#{resultset_path}*")
      end

      def expect_merged
        merged_lines = [1, 1, 2, 2, nil, nil, 2, 2, nil, nil]
        expected = {
          "result1, result2" => {
            "coverage" => {source_fixture("sample.rb") => {"lines" => merged_lines}}
          }
        }
        expect(collated).to eq(expected)
      end
    end
  end

  # Normally wouldn't test private methods but just start has side effects that
  # cause errors so for time this is pragmatic (tm)
  describe ".start_coverage_measurement" do
    after do
      # SimpleCov is a Singleton/global object so once any test enables
      # any kind of coverage data it stays there.
      # Hence, we use clear_coverage_data to create a "clean slate" for these tests
      described_class.clear_coverage_criteria
    end

    before do
      # `start_coverage_with_criteria` short-circuits with `unless
      # Coverage.running?`. These tests verify the kwargs handed to
      # Coverage.start, which only fire when Coverage isn't already
      # running — so stub the running check to false. (Without this,
      # the test would fail when run with the dogfood bootstrap, which
      # starts Coverage before requiring simplecov.)
      allow(Coverage).to receive(:running?).and_return(false)
    end

    it "starts coverage in lines mode by default" do
      allow(Coverage).to receive(:start)

      described_class.send :start_coverage_measurement

      expect(Coverage).to have_received(:start).with({lines: true})
    end

    it "starts coverage with lines and branches if branches is activated" do
      allow(Coverage).to receive(:start)
      described_class.enable_coverage :branch

      described_class.send :start_coverage_measurement

      expect(Coverage).to have_received(:start).with({lines: true, branches: true})
    end

    it "starts coverage with lines and methods if method coverage is activated" do
      allow(Coverage).to receive(:start)
      described_class.enable_coverage :method

      described_class.send :start_coverage_measurement

      expect(Coverage).to have_received(:start).with({lines: true, methods: true})
    end
  end
end
