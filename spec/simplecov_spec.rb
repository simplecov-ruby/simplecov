# frozen_string_literal: true

require "helper"
require "coverage"

RSpec.describe SimpleCov, mutant_expression: ["SimpleCov*", "SimpleCov::Configuration*"] do
  describe ".install_at_exit_hook", mutant_expression: "SimpleCov.install_at_exit_hook" do
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
        klass.class_variable_set(:@@installed_at_exit, true)
        klass
      end

      before { stub_const("Minitest", fake_minitest) }

      it "sets external_at_exit and registers Minitest.after_run" do
        allow(Kernel).to receive(:at_exit)
        described_class.install_at_exit_hook

        expect(described_class.external_at_exit?).to be(true)
        expect(fake_minitest.after_run_blocks.size).to eq(1)
      end

      it "does not defer in a forked child, whose deferral target can never fire" do
        allow(Kernel).to receive(:at_exit)
        allow(described_class).to receive(:forked_subprocess?).and_return(true)
        allow(fake_minitest).to receive(:after_run)

        described_class.install_at_exit_hook

        expect(described_class).not_to be_external_at_exit
        expect(fake_minitest).not_to have_received(:after_run)
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
      fake_minitest.class_variable_set(:@@installed_at_exit, false)
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

  describe ".start", mutant_expression: "SimpleCov.start" do
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

    it "hands the profile and the block it was called with to initial_setup" do
      received_args = nil
      received_block = nil
      allow(described_class).to receive(:initial_setup) do |*args, &block|
        received_args = args
        received_block = block
      end
      allow(described_class).to receive_messages(start_tracking: nil, install_at_exit_hook: nil)
      block = proc {}

      described_class.start("rails", &block)

      expect(received_args).to eq(["rails"])
      expect(received_block).to be(block)
    end

    it "says nothing about `.simplecov` when it is not the autoloader calling" do
      previous = described_class.instance_variable_get(:@autoloading_dot_simplecov)
      described_class.instance_variable_set(:@autoloading_dot_simplecov, nil)
      allow(described_class).to receive_messages(initial_setup: nil, start_tracking: nil,
                                                 install_at_exit_hook: nil,
                                                 warn_about_start_in_dot_simplecov: nil)

      described_class.start

      expect(described_class).not_to have_received(:warn_about_start_in_dot_simplecov)
    ensure
      described_class.instance_variable_set(:@autoloading_dot_simplecov, previous)
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

  describe ".with_dot_simplecov_autoload", mutant_expression: "SimpleCov.with_dot_simplecov_autoload" do
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

  describe ".initial_setup", mutant_expression: "SimpleCov.initial_setup" do
    it "loads the profile when given" do
      allow(described_class).to receive_messages(load_profile: nil, configure: nil)
      described_class.send(:initial_setup, "rails")
      expect(described_class).to have_received(:load_profile).with("rails")
    end

    it "calls configure with the block it was given" do
      received = nil
      allow(described_class).to receive(:configure) { |&block| received = block }
      block = proc {}

      described_class.send(:initial_setup, nil, &block)

      expect(received).to be(block)
    end

    it "leaves configure alone when no block is given" do
      allow(described_class).to receive_messages(load_profile: nil, configure: nil)

      described_class.send(:initial_setup, "rails")

      expect(described_class).not_to have_received(:configure)
    end
  end

  # Named for the caller it protects, but what it exercises is the
  # validation itself, which is where its coverage belongs.
  describe "starting with all criteria disabled",
           mutant_expression: "SimpleCov::Configuration#validate_coverage_criteria!" do
    it "raises a ConfigurationError" do
      previous = described_class.coverage_criteria.dup
      previous.each { |c| described_class.disable_coverage(c) }
      expect { described_class.validate_coverage_criteria! }
        .to raise_error(SimpleCov::ConfigurationError, /At least one coverage criterion/)
    ensure
      previous.each { |c| described_class.enable_coverage(c) }
    end

    it "says nothing while a criterion is still enabled" do
      expect(described_class.coverage_criteria).not_to be_empty

      expect { described_class.validate_coverage_criteria! }.not_to raise_error
    end
  end

  describe ".start_tracking", mutant_expression: "SimpleCov.start_tracking" do
    # Everything it sets up, watched rather than executed: starting
    # measurement for real would instrument the process running these
    # examples.
    around do |example|
      previous = described_class.current_run
      described_class.current_run = SimpleCov::CurrentRun.new
      example.run
    ensure
      described_class.current_run = previous
    end

    before do
      allow(described_class).to receive(:start_coverage_measurement)
      allow(SimpleCov::RunIdentity).to receive(:prepare)
    end

    it "forgets any result the process was holding" do
      described_class.current_run.result = :stale

      described_class.start_tracking
      expect(described_class.result?).to be(false)
    end

    # A forked child restarting tracking must not forget it was forked,
    # and a parent must not recount its subprocess serials from zero.
    it "carries the fork genealogy into the new run" do
      described_class.mark_forked_subprocess!
      described_class.next_subprocess_serial!

      described_class.start_tracking

      expect(described_class).to be_forked_subprocess
      expect(described_class.subprocess_serial).to eq(1)
    end

    # The pid is what tells a forked child it is not the process that
    # started, so it has to be this process's own.
    it "records the process it started in" do
      described_class.pid = -1

      described_class.start_tracking
      expect(described_class.pid).to eq(Process.pid)
    end

    it "records when it started" do
      described_class.process_start_time = nil

      described_class.start_tracking
      expect(described_class.process_start_time).to be_within(5).of(Time.now)
    end

    # Both are settled before anything can fork, so every child inherits
    # one answer rather than deciding its own.
    it "settles the run identity before measurement begins" do
      described_class.start_tracking

      expect(SimpleCov::RunIdentity).to have_received(:prepare).ordered
      expect(described_class).to have_received(:start_coverage_measurement).ordered
    end

    it "refuses to start when no criterion is left to measure" do
      criteria = described_class.coverage_criteria.dup
      criteria.each { |criterion| described_class.disable_coverage(criterion) }

      expect { described_class.start_tracking }.to raise_error(SimpleCov::ConfigurationError)
      expect(described_class).not_to have_received(:start_coverage_measurement)
    ensure
      criteria.each { |criterion| described_class.enable_coverage(criterion) }
    end

    # Watched rather than performed: loading the hook prepends a fork
    # wrapper to Process for the rest of this process's life.
    describe "the subprocess fork hook" do
      before { allow(described_class).to receive(:require_relative) }

      it "is loaded when subprocess support is on and the hook point exists" do
        allow(described_class).to receive(:enabled_for_subprocesses?).and_return(true)
        allow(Process).to receive(:respond_to?).and_call_original
        allow(Process).to receive(:respond_to?).with(:_fork).and_return(true)

        described_class.start_tracking
        expect(described_class).to have_received(:require_relative).with("simplecov/process")
      end

      it "is left alone when subprocess support is off" do
        allow(described_class).to receive(:enabled_for_subprocesses?).and_return(false)

        described_class.start_tracking
        expect(described_class).not_to have_received(:require_relative)
      end

      # Older rubies have no `_fork` to hook, so there is nothing the
      # setting can turn on.
      it "is left alone where Process has no fork hook to prepend to" do
        allow(described_class).to receive(:enabled_for_subprocesses?).and_return(true)
        allow(Process).to receive(:respond_to?).and_call_original
        allow(Process).to receive(:respond_to?).with(:_fork).and_return(false)

        described_class.start_tracking
        expect(described_class).not_to have_received(:require_relative)
      end
    end

    it "makes sure Coverage is loaded before measuring with it" do
      allow(described_class).to receive(:require)

      described_class.start_tracking
      expect(described_class).to have_received(:require).with("coverage")
    end

    it "says so where JRuby cannot report full traces" do
      allow(described_class).to receive(:warn_if_jruby_full_trace_disabled)

      described_class.start_tracking
      expect(described_class).to have_received(:warn_if_jruby_full_trace_disabled)
    end
  end

  # `Result#to_hash` serializes coverage after filtering, so a file this process
  # loaded and then filtered out would be absent from the stored coverage while
  # still listed as tracked, and a merge elsewhere would simulate it back in as
  # never-loaded. Recording only what was tracked and not loaded avoids that.
  # See #1250.
  describe "the tracked paths recorded on a result", mutant_expression: "SimpleCov.process_coverage_result" do
    around do |example|
      previous_cover = described_class.cover_filters.dup
      previous_filters = described_class.filters.dup
      example.run
    ensure
      described_class.instance_variable_set(:@cover_filters, previous_cover)
      described_class.instance_variable_set(:@filters, previous_filters)
    end

    # Every step the method takes, watched: templates compiled in,
    # entries outside the root dropped, the raw hash adapted, and the
    # result built from the pieces those produced.
    describe "what it does with the coverage it collected" do
      let(:sample) { File.expand_path("spec/fixtures/sample.rb", described_class.root) }
      let(:raw) { {sample => {"lines" => [1, 1]}} }

      before do
        allow(Coverage).to receive_messages(running?: true, result: raw)
        allow(SimpleCov::ViewCoverage).to receive(:compile_unrendered)
      end

      it "compiles the templates nothing rendered, so they arrive at nothing rather than absent" do
        described_class.send(:process_coverage_result, report: false, inject_unloaded: false)

        expect(SimpleCov::ViewCoverage).to have_received(:compile_unrendered)
      end

      it "drops what lies outside the project before anything else reads it" do
        allow(SimpleCov::UselessResultsRemover).to receive(:call).and_return({})

        described_class.send(:process_coverage_result, report: false, inject_unloaded: false)

        expect(SimpleCov::UselessResultsRemover).to have_received(:call).with(raw)
        expect(described_class.result.filenames).to be_empty
      end

      it "adapts the raw hash that survived the filtering" do
        allow(SimpleCov::UselessResultsRemover).to receive(:call).and_return(raw)
        allow(SimpleCov::ResultAdapter).to receive(:call).and_call_original

        described_class.send(:process_coverage_result, report: false, inject_unloaded: false)

        expect(SimpleCov::ResultAdapter).to have_received(:call).with(raw)
      end

      # Handed the adapted coverage and the paths that were tracked but
      # not loaded, in that order: the first says what is there, the
      # second what has to be filled in.
      it "injects the tracked files it was asked to, and carries what was injected" do
        described_class.cover "spec/fixtures/*.rb"
        allow(described_class).to receive(:inject_unloaded_files).and_return([{}, Set["injected.rb"]])
        allow(SimpleCov::Result).to receive(:new).and_call_original

        described_class.send(:process_coverage_result, report: false, inject_unloaded: true)

        expect(described_class).to have_received(:inject_unloaded_files)
          .with(a_hash_including(sample), a_collection_including(a_string_ending_with(".rb")))
        expect(SimpleCov::Result)
          .to have_received(:new).with({}, hash_including(not_loaded_files: Set["injected.rb"]))
      end

      # Injection is what the at-exit path wants, so it is what a caller
      # gets without saying so.
      it "injects by default" do
        allow(described_class).to receive(:inject_unloaded_files).and_return([{}, Set.new])

        described_class.send(:process_coverage_result, report: false)
        expect(described_class).to have_received(:inject_unloaded_files)
      end

      it "injects nothing when it was asked not to, and carries the coverage as adapted" do
        allow(described_class).to receive(:inject_unloaded_files)
        allow(SimpleCov::Result).to receive(:new).and_call_original

        described_class.send(:process_coverage_result, report: false, inject_unloaded: false)

        expect(described_class).not_to have_received(:inject_unloaded_files)
        expect(SimpleCov::Result).to have_received(:new).with(anything, hash_including(not_loaded_files: Set.new))
      end

      # The identity is stamped on the result so a merge can tell which
      # run and which worker produced it.
      it "stamps the run and the worker on the result" do
        described_class.send(:process_coverage_result, report: false, inject_unloaded: false)

        expect(described_class.result.run_id).to eq(described_class.run_id)
        expect(described_class.result.worker_id).to eq(described_class.worker_id)
      end

      it "carries whether the result is the one to report" do
        allow(SimpleCov::Result).to receive(:new).and_call_original

        described_class.send(:process_coverage_result, report: true, inject_unloaded: false)
        expect(SimpleCov::Result).to have_received(:new).with(anything, hash_including(report: true))

        described_class.send(:process_coverage_result, report: false, inject_unloaded: false)
        expect(SimpleCov::Result).to have_received(:new).with(anything, hash_including(report: false))
      end

      # The map is taken while the coverage that closed it is in hand,
      # since reading it later would find measurement already stopped.
      it "closes the test map against the coverage it just read" do
        tracker = instance_double(SimpleCov::TestTracker, recorded_map: :the_map)
        allow(described_class).to receive(:test_tracker).and_return(tracker)

        described_class.send(:process_coverage_result, report: false, inject_unloaded: false)

        expect(tracker).to have_received(:recorded_map).with(closing: raw)
        expect(described_class.result.contexts).to be(:the_map)
      end

      it "records no contexts where nothing was tracking tests" do
        allow(described_class).to receive(:test_tracker).and_return(nil)

        described_class.send(:process_coverage_result, report: false, inject_unloaded: false)
        expect(described_class.result.contexts).to be_nil
      end
    end

    it "excludes files this process loaded" do
      described_class.cover "spec/fixtures/*.rb"
      sample = File.expand_path("spec/fixtures/sample.rb", described_class.root)
      allow(Coverage).to receive_messages(running?: true, result: {sample => {"lines" => [1, 1]}})

      described_class.send(:process_coverage_result, report: false, inject_unloaded: false)

      expect(described_class.result.tracked_files).not_to include(sample)
    end

    # Before injection moved to the merge, the producer filtered these out of
    # its own result and they never reached a resultset. Recording them would
    # let a merge that does not share the filter report them at 0%.
    it "excludes files its own path filters keep out of its report" do
      described_class.cover "spec/fixtures/**/*.rb"
      described_class.skip "app/models"
      excluded = File.expand_path("spec/fixtures/app/models/user.rb", described_class.root)
      allow(Coverage).to receive_messages(running?: true, result: {})

      described_class.send(:process_coverage_result, report: false, inject_unloaded: false)

      expect(described_class.result.tracked_files).not_to include(excluded)
    end

    # A block filter is handed the source file and may consult coverage that
    # does not exist yet, so it is left to the merging process's filter chain.
    it "keeps files only a block filter would exclude" do
      described_class.cover "spec/fixtures/*.rb"
      described_class.filters << SimpleCov::BlockFilter.new(
        ->(source_file) { source_file.filename.include?("sample") }
      )
      sample = File.expand_path("spec/fixtures/sample.rb", described_class.root)
      allow(Coverage).to receive_messages(running?: true, result: {})

      described_class.send(:process_coverage_result, report: false, inject_unloaded: false)

      expect(described_class.result.tracked_files).to include(sample)
    end

    it "still records the ones it did not load" do
      described_class.cover "spec/fixtures/*.rb"
      sample = File.expand_path("spec/fixtures/sample.rb", described_class.root)
      other = File.expand_path("spec/fixtures/resultset1.rb", described_class.root)
      allow(Coverage).to receive_messages(running?: true, result: {sample => {"lines" => [1, 1]}})

      described_class.send(:process_coverage_result, report: false, inject_unloaded: false)

      expect(described_class.result.tracked_files).to include(other)
    end

    # The Accessors specs cover this too; asserting the public contract
    # here as well keeps the no-tracker path exercised from more than one
    # spec file, so a parallel run records it in more than one worker.
    it "runs a track_test block untouched when tracking never started" do
      expect(described_class.test_tracker).to be_nil
      expect(described_class.track_test("spec/a_spec.rb:1") { :ran }).to eq(:ran)
    end

    it "records the live per-test map on the result slice, unless the tracker distrusts it" do
      map = SimpleCov::ContextMap.new
      tracker = instance_double(SimpleCov::TestTracker)
      allow(tracker).to receive(:recorded_map).with(closing: anything).and_return(map)
      described_class.instance_variable_set(:@test_tracker, tracker)
      allow(Coverage).to receive_messages(running?: true, result: {})

      described_class.send(:process_coverage_result, report: false, inject_unloaded: false)

      expect(described_class.result.contexts).to be(map)
    ensure
      described_class.remove_instance_variable(:@test_tracker)
    end
  end

  describe ".inject_unloaded_files", mutant_expression: "SimpleCov.inject_unloaded_files" do
    # Discovery and injection are separate now, so exercise them as the pair
    # `process_coverage_result` uses.
    def inject_tracked(result)
      SimpleCov.inject_unloaded_files(result, SimpleCov.send(:tracked_file_paths))
    end

    # What the injector is asked for, rather than what it produces:
    # parsing a file it need not parse is the cost this defaulting
    # exists to avoid.
    around do |example|
      previous_tracked = described_class.tracked_files
      previous_cover = described_class.cover_filters.dup
      example.run
    ensure
      described_class.instance_variable_set(:@tracked_files, previous_tracked)
      described_class.instance_variable_set(:@cover_filters, previous_cover)
    end

    describe "what it asks the injector to synthesize" do
      before { allow(SimpleCov::UnloadedFileInjector).to receive(:call).and_return([{}, Set.new]) }

      def inject(**options)
        described_class.inject_unloaded_files({}, ["lib/a.rb"], **options)
      end

      it "asks for nothing when there are no candidates, without troubling the injector" do
        expect(described_class.inject_unloaded_files({"a" => 1}, [])).to eq([{"a" => 1}, Set.new])
        expect(SimpleCov::UnloadedFileInjector).not_to have_received(:call)
      end

      it "synthesizes tuples when branch coverage is measured" do
        allow(described_class).to receive_messages(branch_coverage?: true, method_coverage?: false)

        inject
        expect(SimpleCov::UnloadedFileInjector).to have_received(:call)
          .with({}, ["lib/a.rb"], hash_including(synthesize: true))
      end

      it "synthesizes tuples when method coverage is measured" do
        allow(described_class).to receive_messages(branch_coverage?: false, method_coverage?: true)

        inject
        expect(SimpleCov::UnloadedFileInjector).to have_received(:call)
          .with(anything, anything, hash_including(synthesize: true))
      end

      # Nothing reads those tuples when neither criterion is on, and
      # producing them means parsing every file that was never loaded.
      it "synthesizes nothing when neither criterion is measured" do
        allow(described_class).to receive_messages(branch_coverage?: false, method_coverage?: false)

        inject
        expect(SimpleCov::UnloadedFileInjector).to have_received(:call)
          .with(anything, anything, hash_including(synthesize: false))
      end

      it "takes the caller's word over the criteria" do
        allow(described_class).to receive_messages(branch_coverage?: true, method_coverage?: true,
                                                   line_coverage?: true)

        inject(synthesize: false, lines: false)
        expect(SimpleCov::UnloadedFileInjector).to have_received(:call)
          .with(anything, anything, {synthesize: false, lines: false})
      end

      it "simulates lines when line coverage is measured, and not otherwise" do
        allow(described_class).to receive(:line_coverage?).and_return(true)
        inject
        expect(SimpleCov::UnloadedFileInjector).to have_received(:call)
          .with(anything, anything, hash_including(lines: true))

        allow(described_class).to receive(:line_coverage?).and_return(false)
        inject
        expect(SimpleCov::UnloadedFileInjector).to have_received(:call)
          .with(anything, anything, hash_including(lines: false))
      end
    end

    it "returns the input unchanged when no discovery glob is configured" do
      result = {"/abs/foo.rb" => {"lines" => [1]}}
      expect(inject_tracked(result)).to eq([result, Set.new])
    end

    it "augments the result with files matched by a cover glob that weren't loaded" do
      described_class.cover "spec/fixtures/sample.rb"
      sample = File.expand_path("spec/fixtures/sample.rb", described_class.root)
      result, not_loaded = inject_tracked({})
      expect(not_loaded).to include(sample)
      expect(result).to have_key(sample)
    end

    it "skips files that are already present in the input result" do
      described_class.cover "spec/fixtures/sample.rb"
      sample = File.expand_path("spec/fixtures/sample.rb", described_class.root)
      preloaded = {sample => {"lines" => [1]}}
      result, not_loaded = inject_tracked(preloaded)
      expect(not_loaded).not_to include(sample)
      expect(result[sample]).to eq("lines" => [1])
    end

    # The discovery glob has to be project-root-relative, not cwd-
    # relative — test runners that chdir would otherwise silently miss
    # unloaded files and emit different file sets per environment. See #1106.
    it "resolves the glob relative to SimpleCov.root regardless of cwd" do
      described_class.cover "spec/fixtures/sample.rb"
      sample = File.expand_path(File.join(described_class.root, "spec/fixtures/sample.rb"))
      Dir.chdir(Dir.tmpdir) do
        _result, not_loaded = inject_tracked({})
        expect(not_loaded).to include(sample)
      end
    end

    it "still honors the legacy track_files glob" do
      capture_stderr { described_class.track_files("spec/fixtures/sample.rb") }
      sample = File.expand_path("spec/fixtures/sample.rb", described_class.root)
      _result, not_loaded = inject_tracked({})
      expect(not_loaded).to include(sample)
    end

    # Synthesizing branch and method tuples for an unloaded file means parsing
    # it, which is about half the cost of simulating one and is paid per
    # tracked file per process. Nothing reads the tuples unless the matching
    # criterion is enabled. See #1250.
    context "when neither branch nor method coverage is enabled" do
      it "skips synthesizing branch and method tuples" do
        allow(described_class).to receive_messages(branch_coverage?: false, method_coverage?: false)
        described_class.cover "spec/fixtures/sample.rb"
        sample = File.expand_path("spec/fixtures/sample.rb", described_class.root)
        result, = inject_tracked({})
        expect(result[sample]["branches"]).to be_empty
        expect(result[sample]["methods"]).to be_empty
      end

      it "still classifies the file's lines" do
        allow(described_class).to receive_messages(branch_coverage?: false, method_coverage?: false)
        described_class.cover "spec/fixtures/sample.rb"
        sample = File.expand_path("spec/fixtures/sample.rb", described_class.root)
        result, = inject_tracked({})
        expect(result[sample]["lines"]).to be_an(Array).and(be_any { |count| !count.nil? })
      end
    end

    # A branch-only or method-only run gets no line data from `Coverage` for
    # the files it loaded, so simulating lines for the files it didn't would
    # make the two indistinguishable after merging. See #1250.
    context "when line coverage is disabled" do
      it "omits line data from simulated files" do
        allow(described_class).to receive(:line_coverage?).and_return(false)
        described_class.cover "spec/fixtures/sample.rb"
        sample = File.expand_path("spec/fixtures/sample.rb", described_class.root)
        result, = inject_tracked({})
        expect(result[sample]).not_to have_key("lines")
      end
    end

    context "when a criterion that reads the tuples is enabled" do
      it "synthesizes them", if: SimpleCov::StaticCoverageExtractor.available? do
        allow(described_class).to receive_messages(branch_coverage?: false, method_coverage?: true)
        described_class.cover "spec/fixtures/sample.rb"
        sample = File.expand_path("spec/fixtures/sample.rb", described_class.root)
        result, = inject_tracked({})
        expect(result[sample]["methods"]).not_to be_empty
      end
    end
  end

  describe ".ready_to_process_results?", mutant_expression: "SimpleCov.ready_to_process_results?" do
    around do |example|
      previous = described_class.current_run
      described_class.current_run = SimpleCov::CurrentRun.new
      example.run
    ensure
      described_class.current_run = previous
    end

    # Every way the answer can be no, and the two ways it can be yes.
    describe "what has to be true before results are processed" do
      before do
        allow(described_class).to receive_messages(merge_finalization_owner?: true, result?: true,
                                                   collating_result?: false,
                                                   parallel_results_complete?: true)
      end

      it "is false in a process that does not own the finalization" do
        allow(described_class).to receive(:merge_finalization_owner?).and_return(false)
        expect(described_class.ready_to_process_results?).to be(false)
      end

      it "is false where there is no result to process" do
        allow(described_class).to receive(:result?).and_return(false)
        expect(described_class.ready_to_process_results?).to be(false)
      end

      # A collate has every resultset by definition, so it never waits
      # on siblings.
      it "is true for a collate, whatever the siblings did" do
        allow(described_class).to receive_messages(collating_result?: true,
                                                   parallel_results_complete?: false)
        expect(described_class.ready_to_process_results?).to be(true)
      end

      it "is true for a run whose siblings all reported" do
        expect(described_class.ready_to_process_results?).to be(true)
      end

      # A partial total would fail thresholds that the whole run passes.
      it "is false for a run still missing a sibling" do
        allow(described_class).to receive(:parallel_results_complete?).and_return(false)
        expect(described_class.ready_to_process_results?).to be(false)
      end
    end

    it "is true when the finalization owner has a complete result" do
      allow(described_class).to receive_messages(merge_finalization_owner?: true, result?: true)
      expect(described_class.ready_to_process_results?).to be true
    end

    it "is false when this process does not own merge finalization" do
      allow(described_class).to receive_messages(merge_finalization_owner?: false, result?: true)
      expect(described_class.ready_to_process_results?).to be false
    end

    it "is true for a collated result even when worker parallel results are incomplete" do
      described_class.current_run.collating_result = true
      allow(described_class).to receive_messages(merge_finalization_owner?: true, result?: true,
                                                 parallel_results_complete?: false)

      expect(described_class.ready_to_process_results?).to be true
    end
  end

  describe ".final_result_process?", mutant_expression: "SimpleCov.final_result_process?" do
    it "is true when ParallelTests isn't loaded" do
      expect(described_class.send(:final_result_process?)).to be_truthy
    end

    context "with no adapter and a forked subprocess" do
      it "is false in a forked worker so it doesn't produce the final report" do
        allow(described_class).to receive(:forked_subprocess?).and_return(true)
        expect(described_class.send(:final_result_process?)).to be false
      end

      it "is true in the process that did the forking" do
        allow(described_class).to receive(:forked_subprocess?).and_return(false)
        expect(described_class.send(:final_result_process?)).to be true
      end
    end

    context "when running under a faked parallel_tests setup" do
      # `Class.new { def self.first_process?; end }` rather than a plain
      # Class.new so rspec-mocks 4's verify_partial_doubles check (now
      # on by default) accepts the subsequent `allow(...).to receive(
      # :first_process?)` stubs.
      before do
        stub_const("ParallelTests", Class.new { def self.first_process?; end })
        # SimpleCov::ParallelAdapters.current is memoized after first read
        # (typically during SimpleCov.start at suite boot). Clear it so
        # each example picks up the freshly stubbed ParallelTests + ENV.
        SimpleCov::ParallelAdapters.reset_current!
      end

      around do |example|
        prev_n, prev_g = ENV.values_at("TEST_ENV_NUMBER", "PARALLEL_TEST_GROUPS")
        example.run
      ensure
        ENV["TEST_ENV_NUMBER"] = prev_n
        ENV["PARALLEL_TEST_GROUPS"] = prev_g
        SimpleCov::ParallelAdapters.reset_current!
      end

      # parallel_tests sets the first worker's TEST_ENV_NUMBER to "" and
      # `first_process?` tests for that empty string, so single-group runs
      # (PARALLEL_TEST_GROUPS=1) naturally return true — no explicit
      # GROUPS=1 fallback needed (the old fallback compensated for
      # `last_process?`'s `"" == "1"` mismatch — see #1066).
      it "is true when running with PARALLEL_TEST_GROUPS=1" do
        ENV["TEST_ENV_NUMBER"] = ""
        ENV["PARALLEL_TEST_GROUPS"] = "1"
        allow(ParallelTests).to receive(:first_process?).and_return(true)
        expect(described_class.send(:final_result_process?)).to be true
      end

      it "is true for the first worker in a multi-group run" do
        ENV["TEST_ENV_NUMBER"] = ""
        ENV["PARALLEL_TEST_GROUPS"] = "2"
        allow(ParallelTests).to receive(:first_process?).and_return(true)
        expect(described_class.send(:final_result_process?)).to be true
      end

      it "is false for a non-first worker in a multi-group run" do
        ENV["TEST_ENV_NUMBER"] = "2"
        ENV["PARALLEL_TEST_GROUPS"] = "2"
        allow(ParallelTests).to receive(:first_process?).and_return(false)
        expect(described_class.send(:final_result_process?)).to be false
      end
    end
  end

  describe ".wait_for_other_processes", mutant_expression: "SimpleCov.wait_for_other_processes" do
    let(:adapter) do
      class_double(SimpleCov::ParallelAdapters::Base, wait_for_siblings: nil,
                                                      expected_worker_count: 3, native_wait?: true)
    end

    around do |example|
      had = described_class.instance_variable_defined?(:@parallel_results_complete)
      previous = described_class.instance_variable_get(:@parallel_results_complete) if had
      example.run
    ensure
      described_class.remove_instance_variable(:@parallel_results_complete) if
        described_class.instance_variable_defined?(:@parallel_results_complete)
      described_class.instance_variable_set(:@parallel_results_complete, previous) if had
    end

    it "returns early when no parallel runner is driving the suite" do
      allow(SimpleCov::ParallelAdapters).to receive(:current).and_return(nil)

      expect(described_class.send(:wait_for_other_processes)).to be_nil
      expect(adapter).not_to have_received(:wait_for_siblings)
    end

    # Only the process that will write the report waits; the others have
    # nothing to wait for and would deadlock each other if they did.
    it "returns early in a worker that is not the one reporting" do
      allow(SimpleCov::ParallelAdapters).to receive(:current).and_return(adapter)
      allow(described_class).to receive(:final_result_process?).and_return(false)

      expect(described_class.send(:wait_for_other_processes)).to be_nil
      expect(adapter).not_to have_received(:wait_for_siblings)
    end

    context "when this is the process that will report" do
      before do
        allow(SimpleCov::ParallelAdapters).to receive(:current).and_return(adapter)
        allow(described_class).to receive_messages(final_result_process?: true, wait_for_parallel_results: true)
      end

      # The runner's own wait first, where there is one, then the poll:
      # a native wait can return before the siblings have finished
      # writing, and an adapter without one has nothing else.
      it "waits on the runner before polling for resultsets" do
        described_class.send(:wait_for_other_processes)

        expect(adapter).to have_received(:wait_for_siblings).ordered
        expect(described_class).to have_received(:wait_for_parallel_results).ordered
      end

      it "polls for as many workers as the adapter expects, saying whether it waited natively" do
        described_class.send(:wait_for_other_processes)

        expect(described_class).to have_received(:wait_for_parallel_results).with(3, native_wait: true)
      end

      # An adapter with no wait primitive of its own says so, and the
      # poll is what has to be patient in that case.
      it "says when there was no native wait to lean on" do
        allow(adapter).to receive(:native_wait?).and_return(false)

        described_class.send(:wait_for_other_processes)
        expect(described_class).to have_received(:wait_for_parallel_results).with(3, native_wait: false)
      end

      it "remembers that every sibling reported" do
        described_class.send(:wait_for_other_processes)
        expect(described_class.parallel_results_complete?).to be(true)
      end

      # Recorded so the threshold checks can tell a partial total from a
      # complete one and stay quiet about it.
      it "remembers when they did not" do
        allow(described_class).to receive(:wait_for_parallel_results).and_return(false)

        described_class.send(:wait_for_other_processes)
        expect(described_class.parallel_results_complete?).to be(false)
      end
    end
  end

  describe ".wait_for_parallel_results", mutant_expression: "SimpleCov.wait_for_parallel_results" do
    it "returns true immediately when expected worker count is 1 (single-process or single-group)" do
      expect(described_class.send(:wait_for_parallel_results, 1)).to be(true)
    end

    it "returns true immediately when expected worker count is 0" do
      expect(described_class.send(:wait_for_parallel_results, 0)).to be(true)
    end

    it "returns true once every expected worker has reported" do
      run_id = described_class.run_id
      resultset = {
        "a" => {"run_id" => run_id, "worker_id" => "1"},
        "b" => {"run_id" => run_id, "worker_id" => "2"}
      }
      allow(SimpleCov::ResultMerger).to receive(:read_resultset).and_return(resultset)
      expect(described_class.send(:wait_for_parallel_results, 2)).to be(true)
    end

    # More workers than expected is still every worker: the count is a
    # floor, not a target to match exactly.
    it "is satisfied by more reports than it expected" do
      allow(described_class).to receive_messages(current_parallel_worker_count: 3, sleep: nil)

      expect(described_class.send(:wait_for_parallel_results, 2)).to be(true)
    end

    # Without a native wait there is nothing to say the siblings have
    # exited, so a steady count proves nothing and the poll runs on.
    it "does not accept a settled count when no native wait ran" do
      allow(described_class).to receive_messages(current_parallel_worker_count: 1, sleep: nil)
      allow(described_class).to receive(:parallel_wait_timed_out?).and_return(false, false, true)

      expect(described_class.send(:wait_for_parallel_results, 4, native_wait: false)).to be(false)
    end

    # A steady count only means something after a native wait proved the
    # siblings had exited; on its own it is just a count that has not
    # moved yet.
    it "ignores a settled count when no native wait ran" do
      allow(described_class).to receive_messages(current_parallel_worker_count: 1, sleep: nil,
                                                 resultset_count_settled?: true)
      allow(described_class).to receive(:parallel_wait_timed_out?).and_return(true)

      expect(described_class.send(:wait_for_parallel_results, 4, native_wait: false)).to be(false)
    end

    # The count starts at nothing and the clock starts now, which is
    # what makes the first report look like movement.
    it "starts tracking from no workers seen, timed from the moment it began" do
      allow(described_class).to receive_messages(current_parallel_worker_count: 1, sleep: nil,
                                                 resultset_count_settled?: false)
      allow(described_class).to receive(:parallel_wait_timed_out?).and_return(true)

      described_class.send(:wait_for_parallel_results, 4, native_wait: true)
      expect(described_class).to have_received(:resultset_count_settled?)
        .with({count: 0, since: an_instance_of(Float)}, 1)
    end

    # A caller that says nothing is a caller with no native wait behind
    # it, so a settled count means nothing to them either.
    it "polls without a native wait unless told there was one" do
      allow(described_class).to receive_messages(current_parallel_worker_count: 1, sleep: nil,
                                                 resultset_count_settled?: true)
      allow(described_class).to receive(:parallel_wait_timed_out?).and_return(true)

      expect(described_class.send(:wait_for_parallel_results, 4)).to be(false)
    end

    # The deadline it was given, the count it wants and the count it has:
    # all three decide whether waiting longer is worth it.
    it "asks about the timeout with the deadline, the expected count and what it has seen" do
      allow(described_class).to receive_messages(current_parallel_worker_count: 1, sleep: nil)
      allow(described_class).to receive(:parallel_wait_timed_out?).and_return(true)

      described_class.send(:wait_for_parallel_results, 4)
      expect(described_class).to have_received(:parallel_wait_timed_out?)
        .with(an_instance_of(Float), 4, 1)
    end

    it "pauses between polls rather than spinning" do
      allow(described_class).to receive_messages(current_parallel_worker_count: 1, sleep: nil)
      allow(described_class).to receive(:parallel_wait_timed_out?).and_return(false, true)

      described_class.send(:wait_for_parallel_results, 4)
      expect(described_class).to have_received(:sleep).with(0.1)
    end

    it "does not count stale entries or forked children as current workers" do
      run_id = described_class.run_id
      partial = {
        "old-1" => {"run_id" => "old-run", "worker_id" => "1"},
        "old-2" => {"run_id" => "old-run", "worker_id" => "2"},
        "current" => {"run_id" => run_id, "worker_id" => "1"},
        "current child" => {"run_id" => run_id, "worker_id" => "1"}
      }
      complete = partial.merge("current-2" => {"run_id" => run_id, "worker_id" => "2"})
      allow(SimpleCov::ResultMerger).to receive(:read_resultset).and_return(partial, complete)
      allow(described_class).to receive(:sleep)

      expect(described_class.send(:wait_for_parallel_results, 2)).to be(true)
      expect(SimpleCov::ResultMerger).to have_received(:read_resultset).twice
    end

    # A native wait already confirmed all sibling processes exited, so a count
    # that holds below `expected` means the extra workers produced nothing
    # (idle parallel_test groups) — accept it as final instead of blocking for
    # the whole timeout.
    it "accepts a settled count below expected as complete when a native wait ran" do
      resultset = {"a" => {"run_id" => described_class.run_id, "worker_id" => "1"}}
      allow(SimpleCov::ResultMerger).to receive(:read_resultset).and_return(resultset)
      allow(described_class).to receive(:sleep)
      allow(described_class).to receive(:parallel_wait_timeout).and_return(60)

      expect(described_class.send(:wait_for_parallel_results, 4, native_wait: true)).to be(true)
    end

    it "does not let stale entries satisfy the native settled-count shortcut" do
      stale = {"old" => {"run_id" => "old-run", "worker_id" => "1", "timestamp" => Time.now.to_f}}
      allow(SimpleCov::ResultMerger).to receive(:read_resultset).and_return(stale)
      allow(described_class).to receive(:sleep)
      allow(described_class).to receive_messages(parallel_wait_timeout: 0, print_errors: false)

      expect(described_class.send(:wait_for_parallel_results, 2, native_wait: true)).to be(false)
    end

    # Without a native wait an idle worker is indistinguishable from a slow
    # one, so keep waiting the full timeout and report the partial result.
    it "times out (partial) on a short count without a native wait" do
      resultset = {"a" => {"run_id" => described_class.run_id, "worker_id" => "1"}}
      allow(SimpleCov::ResultMerger).to receive(:read_resultset).and_return(resultset)
      allow(described_class).to receive(:sleep)
      allow(described_class).to receive_messages(parallel_wait_timeout: 0, print_errors: false)

      expect(described_class.send(:wait_for_parallel_results, 4, native_wait: false)).to be(false)
    end
  end

  describe ".parallel_results_complete?", mutant_expression: "SimpleCov.parallel_results_complete?" do
    around do |example|
      ivar = :@parallel_results_complete
      previous_defined = described_class.instance_variable_defined?(ivar)
      previous = described_class.instance_variable_get(ivar)
      example.run
    ensure
      if previous_defined
        described_class.instance_variable_set(ivar, previous)
      elsif described_class.instance_variable_defined?(ivar)
        described_class.remove_instance_variable(ivar)
      end
    end

    it "defaults to true outside a parallel run" do
      ivar = :@parallel_results_complete
      described_class.remove_instance_variable(ivar) if described_class.instance_variable_defined?(ivar)
      expect(described_class.parallel_results_complete?).to be(true)
    end

    it "is false after wait_for_other_processes reports a timeout" do
      described_class.instance_variable_set(:@parallel_results_complete, false)
      expect(described_class.parallel_results_complete?).to be(false)
    end
  end

  describe ".at_exit_behavior", mutant_expression: "SimpleCov.at_exit_behavior" do
    around do |example|
      previous_pid = described_class.pid
      example.run
      described_class.pid = previous_pid
    end

    # Everything downstream is let through, so the process check is the
    # only thing that can stop this.
    it "is a no-op when called from a different process than start" do
      described_class.pid = -1 # never matches Process.pid
      allow(Coverage).to receive(:running?).and_return(true)
      allow(described_class).to receive_messages(defer_to_existing_report?: false, run_exit_tasks!: nil)

      described_class.at_exit_behavior
      expect(described_class).not_to have_received(:run_exit_tasks!)
    end

    # The status is read before the deferral probe, whose freshness check
    # rescues filesystem errors, and completing a rescue inside an
    # at_exit handler resets the error the suite exited with.
    it "reads the suite's exit status before probing for a fresher report" do
      described_class.pid = Process.pid
      allow(Coverage).to receive(:running?).and_return(true)
      allow(described_class).to receive_messages(exit_status_from_exception: 7,
                                                 defer_to_existing_report?: false, run_exit_tasks!: nil)

      described_class.at_exit_behavior

      expect(described_class).to have_received(:exit_status_from_exception).ordered
      expect(described_class).to have_received(:defer_to_existing_report?).ordered
      expect(described_class).to have_received(:run_exit_tasks!).with(7)
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

    # The deferral probe's freshness check rescues filesystem errors,
    # and completing ANY rescue inside an at_exit handler resets
    # $ERROR_INFO to nil — so the suite's exit status must be captured
    # before the probe runs, or a failing suite reads as clean and its
    # failure status is swallowed.
    it "captures the exit status up front and hands it to run_exit_tasks!" do
      described_class.pid = Process.pid
      allow(Coverage).to receive(:running?).and_return(true)
      allow(described_class).to receive_messages(exit_status_from_exception: 1, defer_to_existing_report?: false)
      allow(described_class).to receive(:run_exit_tasks!)

      described_class.at_exit_behavior

      expect(described_class).to have_received(:run_exit_tasks!).with(1)
    end
  end

  describe ".defer_to_existing_report?", mutant_expression: "SimpleCov.defer_to_existing_report?" do
    let(:tmp) { Dir.mktmpdir }
    let(:last_run_path) { File.join(tmp, ".last_run.json") }

    before { allow(described_class).to receive(:coverage_path).and_return(tmp) }
    after { FileUtils.remove_entry(tmp) }

    # A report that is newer than us but has nothing in it is the case
    # this stands down for; one with files is a report we may replace.
    describe "when there is a newer report on disk" do
      before { allow(described_class).to receive(:existing_report_newer_than_us?).and_return(true) }

      it "stands down, and says so, when this run has no result at all" do
        allow(described_class).to receive_messages(result: nil, warn_about_deferred_report: nil)

        expect(described_class.defer_to_existing_report?).to be(true)
        expect(described_class).to have_received(:warn_about_deferred_report)
      end

      it "stands down, and says so, when this run measured nothing" do
        allow(described_class).to receive_messages(result: SimpleCov::Result.new({}),
                                                   warn_about_deferred_report: nil)

        expect(described_class.defer_to_existing_report?).to be(true)
        expect(described_class).to have_received(:warn_about_deferred_report)
      end

      it "carries on quietly when this run has something to report" do
        result = SimpleCov::Result.new({source_fixture("sample.rb") => {"lines" => [1]}})
        allow(described_class).to receive_messages(result: result, warn_about_deferred_report: nil)

        expect(described_class.defer_to_existing_report?).to be(false)
        expect(described_class).not_to have_received(:warn_about_deferred_report)
      end
    end

    it "is false when process_start_time is unset" do
      allow(described_class).to receive(:process_start_time).and_return(nil)
      expect(described_class.defer_to_existing_report?).to be false
    end

    it "is false when no on-disk last_run report exists" do
      allow(described_class).to receive(:process_start_time).and_return(Time.now)
      expect(described_class.defer_to_existing_report?).to be false
    end

    # .last_run.json is only written by fully successful runs, so keying
    # the backstop on it alone left it inert when the child run FAILED —
    # the case where clobbering its report hurts most. The report stamp
    # is touched by every formatting process regardless of exit status.
    it "defers on a fresh report stamp even without .last_run.json (failed child run)" do
      stamp = File.join(tmp, ".report_stamp")
      FileUtils.touch(stamp)
      future = Time.now + 60
      File.utime(future, future, stamp)
      result = instance_double(SimpleCov::Result, files: [])
      allow(described_class).to receive_messages(process_start_time: Time.now, result: result)
      allow(described_class).to receive(:warn_about_deferred_report)

      expect(described_class.defer_to_existing_report?).to be true
    end

    it "does not raise when the on-disk report vanishes between checks" do
      allow(described_class).to receive(:process_start_time).and_return(Time.now)
      allow(File).to receive(:mtime).and_raise(Errno::ENOENT)

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
        allow(described_class).to receive_messages(result: result, print_errors: true)
        stderr = capture_stderr { described_class.defer_to_existing_report? }
        expect(stderr).to include("Skipping SimpleCov report")
        expect(stderr).to include("581")
      end

      it "still defers but stays silent when print_errors is false" do
        result = instance_double(SimpleCov::Result, files: [])
        allow(described_class).to receive_messages(result: result, print_errors: false)
        stderr = capture_stderr do
          expect(described_class.defer_to_existing_report?).to be true
        end
        expect(stderr).to be_empty
      end
    end
  end

  describe ".run_exit_tasks", mutant_expression: "SimpleCov.run_exit_tasks" do
    it "runs the configured at_exit block before deciding anything" do
      ran = []
      allow(described_class).to receive_messages(at_exit: -> { ran << :at_exit },
                                                 exit_status_from_exception: nil,
                                                 previous_error?: false, ready_to_process_results?: true,
                                                 result: instance_double(SimpleCov::Result))
      allow(described_class).to receive(:process_result) {
        ran << :processed
        0
      }

      described_class.run_exit_tasks
      expect(ran).to eq(%i[at_exit processed])
    end

    it "answers the previous error's own status, reported but not processed" do
      allow(described_class).to receive_messages(at_exit: proc {}, exit_status_from_exception: 7,
                                                 ready_to_process_results?: true)
      allow(described_class).to receive(:report_previous_error)
      allow(described_class).to receive(:process_result)

      expect(described_class.run_exit_tasks).to eq(7)
      expect(described_class).to have_received(:report_previous_error)
      expect(described_class).not_to have_received(:process_result)
    end

    it "answers what processing this run's result decides when the run is ready" do
      collected = instance_double(SimpleCov::Result)
      allow(described_class).to receive_messages(at_exit: proc {}, exit_status_from_exception: nil,
                                                 ready_to_process_results?: true, result: collected)
      allow(described_class).to receive(:report_processing_failure) { |status| status }
      allow(described_class).to receive(:process_result).and_return(3)

      expect(described_class.run_exit_tasks).to eq(3)
      expect(described_class).to have_received(:process_result).with(collected)
      expect(described_class).to have_received(:report_processing_failure).with(3)
    end

    # Not processing is asserted too: without it, a run that processes
    # anyway can land on the same status and pass by coincidence.
    it "answers success, exactly, when there is nothing to process" do
      allow(described_class).to receive_messages(at_exit: proc {}, exit_status_from_exception: nil,
                                                 ready_to_process_results?: false)
      allow(described_class).to receive(:process_result)

      expect(described_class.run_exit_tasks).to eql(SimpleCov::ExitCodes::SUCCESS)
      expect(described_class).not_to have_received(:process_result)
    end

    it "asks about the status it was given rather than looking it up again" do
      allow(described_class).to receive_messages(at_exit: proc {}, previous_error?: false,
                                                 ready_to_process_results?: false,
                                                 exit_status_from_exception: 9)

      described_class.run_exit_tasks(4)
      expect(described_class).to have_received(:previous_error?).with(4)
    end

    it "looks the status up when a caller hands none in" do
      allow(described_class).to receive_messages(at_exit: proc {}, previous_error?: false,
                                                 ready_to_process_results?: false,
                                                 exit_status_from_exception: 9)

      described_class.run_exit_tasks
      expect(described_class).to have_received(:previous_error?).with(9)
    end

    it "never ends the process itself, whatever it answers" do
      allow(Kernel).to receive(:exit)
      allow(described_class).to receive_messages(at_exit: proc {}, exit_status_from_exception: 7,
                                                 print_errors: false, ready_to_process_results?: false)

      expect(described_class.run_exit_tasks).to eq(7)
      expect(Kernel).not_to have_received(:exit)
    end
  end

  describe ".run_exit_tasks!", mutant_expression: "SimpleCov.run_exit_tasks!" do
    it "ends the process with the failing status the tasks answered" do
      allow(Kernel).to receive(:exit)
      allow(described_class).to receive(:run_exit_tasks).and_return(3)

      described_class.run_exit_tasks!(3)

      expect(Kernel).to have_received(:exit).with(3)
    end

    it "hands the status it was given through to the tasks" do
      allow(Kernel).to receive(:exit)
      allow(described_class).to receive(:run_exit_tasks).and_return(0)

      described_class.run_exit_tasks!(4)

      expect(described_class).to have_received(:run_exit_tasks).with(4)
    end

    it "looks the status up when a caller hands none in" do
      allow(Kernel).to receive(:exit)
      allow(described_class).to receive_messages(exit_status_from_exception: 9, run_exit_tasks: 0)

      described_class.run_exit_tasks!

      expect(described_class).to have_received(:run_exit_tasks).with(9)
    end

    it "lets a successful run fall through to the runtime's own exit" do
      allow(Kernel).to receive(:exit)
      allow(described_class).to receive(:run_exit_tasks).and_return(SimpleCov::ExitCodes::SUCCESS)

      described_class.run_exit_tasks!

      expect(Kernel).not_to have_received(:exit)
    end
  end

  describe ".collate finalization", mutant_expression: "SimpleCov.collate" do
    after { described_class.clear_result }

    it "finalizes and writes last_run even when ordinary worker finalization is disabled" do
      result = instance_double(SimpleCov::Result)
      allow(SimpleCov::ResultMerger).to receive(:merge_and_store).and_return(result)
      allow(described_class).to receive_messages(at_exit: proc {}, finalize_merge?: false,
                                                 final_result_process?: false,
                                                 result_exit_status: SimpleCov::ExitCodes::SUCCESS)
      allow(described_class).to receive(:write_last_run)
      allow(SimpleCov::History).to receive(:record)

      described_class.collate(["coverage/worker/.resultset.json"])

      expect(SimpleCov::ResultMerger).to have_received(:merge_and_store)
        .with("coverage/worker/.resultset.json", ignore_timeout: true)
      expect(described_class).to have_received(:write_last_run).with(result)
      expect(SimpleCov::History).to have_received(:record).with(result)
    end
  end

  describe ".previous_error?", mutant_expression: "SimpleCov.previous_error?" do
    it "is truthy for a non-success exit status" do
      expect(described_class).to be_previous_error(SimpleCov::ExitCodes::MINIMUM_COVERAGE)
    end

    it "answers with a boolean rather than the status it was handed" do
      expect(described_class.previous_error?(SimpleCov::ExitCodes::MINIMUM_COVERAGE)).to be(true)
    end

    it "answers false, not nil, for a status it was never given" do
      expect(described_class.previous_error?(nil)).to be(false)
    end

    it "is falsey for SUCCESS" do
      expect(described_class).not_to be_previous_error(SimpleCov::ExitCodes::SUCCESS)
    end

    it "is falsey for nil" do
      expect(described_class).not_to be_previous_error(nil)
    end
  end

  describe ".report_previous_error", mutant_expression: "SimpleCov.report_previous_error" do
    it "warns when print_errors is true, and does not end the process" do
      allow(described_class).to receive(:print_errors).and_return(true)
      allow(Kernel).to receive(:exit)
      stderr = capture_stderr { described_class.report_previous_error }
      expect(stderr).to include("Stopped processing SimpleCov")
      expect(Kernel).not_to have_received(:exit)
    end

    it "is silent when print_errors is false" do
      allow(described_class).to receive(:print_errors).and_return(false)
      stderr = capture_stderr { described_class.report_previous_error }
      expect(stderr).to be_empty
    end

    it "colors the notice yellow, the shade it reserves for someone else's error" do
      allow(described_class).to receive(:print_errors).and_return(true)
      allow(SimpleCov::Color).to receive(:colorize).and_return("colorized")

      capture_stderr { described_class.report_previous_error }

      expect(SimpleCov::Color)
        .to have_received(:colorize).with(/\AStopped processing SimpleCov /, :yellow)
    end
  end

  describe ".report_processing_failure", mutant_expression: "SimpleCov.report_processing_failure" do
    it "answers the failing status it was handed, and explains it" do
      allow(described_class).to receive(:print_errors).and_return(true)

      stderr = capture_stderr { expect(described_class.report_processing_failure(2)).to eq(2) }

      expect(stderr).to include("SimpleCov failed with exit 2")
    end

    it "answers success silently, which needs no explaining" do
      allow(described_class).to receive(:print_errors).and_return(true)

      stderr = capture_stderr { expect(described_class.report_processing_failure(0)).to eq(0) }

      expect(stderr).to be_empty
    end

    it "stays silent when print_errors is off, but still answers the status" do
      allow(described_class).to receive(:print_errors).and_return(false)

      stderr = capture_stderr { expect(described_class.report_processing_failure(2)).to eq(2) }

      expect(stderr).to be_empty
    end

    it "colors the failure red, the shade it reserves for its own" do
      allow(described_class).to receive_messages(print_errors: true)
      allow(SimpleCov::Color).to receive(:colorize).and_return("colorized")

      capture_stderr { described_class.report_processing_failure(2) }

      expect(SimpleCov::Color).to have_received(:colorize).with(/\ASimpleCov failed with exit /, :red)
    end

    it "never ends the process itself" do
      allow(Kernel).to receive(:exit)
      allow(described_class).to receive(:print_errors).and_return(false)

      described_class.report_processing_failure(2)

      expect(Kernel).not_to have_received(:exit)
    end
  end

  describe ".grouped", mutant_expression: "SimpleCov.grouped" do
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
      described_class.group("Lib", "lib")
      result = described_class.grouped(files)
      expect(result.keys).to contain_exactly("Lib", "Ungrouped")
      expect(result["Lib"].map(&:project_filename)).to eq(["lib/foo.rb"])
      expect(result["Ungrouped"].map(&:project_filename)).to eq(["test/foo.rb"])
    end

    it "hands back file lists, which is what a group is asked to report on" do
      described_class.group("Lib", "lib")

      result = described_class.grouped(files)

      expect(result["Lib"]).to be_a(SimpleCov::FileList)
      expect(result["Ungrouped"]).to be_a(SimpleCov::FileList)
    end

    it "skips Ungrouped when every file matches a group" do
      described_class.group("All", //)
      result = described_class.grouped(files)
      expect(result.keys).to contain_exactly("All")
    end

    it "rejects a reserved group inserted by direct hash mutation" do
      described_class.groups["Ungrouped"] = SimpleCov::StringFilter.new("lib")

      expect { described_class.grouped(files) }
        .to raise_error(SimpleCov::ConfigurationError, /reserved/)
    end
  end

  describe ".unloaded_file_discovery_globs", mutant_expression: "SimpleCov.unloaded_file_discovery_globs" do
    it "lays the cover globs out beside the tracked-files one rather than nesting them" do
      allow(described_class).to receive_messages(tracked_files: "lib/**/*.rb",
                                                 cover_globs: ["app/**/*.rb", "config/**/*.rb"])

      expect(described_class.send(:unloaded_file_discovery_globs))
        .to eq(["lib/**/*.rb", "app/**/*.rb", "config/**/*.rb"])
    end

    it "drops the tracked-files glob when none was configured" do
      allow(described_class).to receive_messages(tracked_files: nil, cover_globs: ["app/**/*.rb"])

      expect(described_class.send(:unloaded_file_discovery_globs)).to eq(["app/**/*.rb"])
    end
  end

  describe ".write_last_run", mutant_expression: "SimpleCov.write_last_run" do
    it "records each criterion's percentage rounded down to two decimals" do
      result = instance_double(
        SimpleCov::Result,
        coverage_statistics: {
          line: instance_double(SimpleCov::CoverageStatistics, percent: 89.456789),
          branch: instance_double(SimpleCov::CoverageStatistics, percent: 74.999999)
        }
      )
      allow(SimpleCov::LastRun).to receive(:write)

      described_class.write_last_run(result)

      expect(SimpleCov::LastRun).to have_received(:write).with(result: {line: 89.45, branch: 74.99})
    end
  end

  describe ".result", mutant_expression: ["SimpleCov.result", "SimpleCov.merge_own_slice"] do
    before do
      described_class.clear_result
      allow(Coverage).to receive(:result).once.and_return({})
    end

    context "with merging disabled" do
      before do
        allow(described_class).to receive(:merging).once.and_return(false)
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
          allow(described_class).to receive(:inject_unloaded_files).and_return([{}, Set.new])
          described_class.result
          expect(described_class).to have_received(:inject_unloaded_files).once
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
        allow(described_class).to receive(:merging).twice.and_return(true)
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

        # With a merge step to follow, only the union of every process's loaded
        # files says what was never loaded, so injection is deferred to
        # `ResultMerger.create_result` (stubbed out in this context). Injecting
        # per process would simulate nearly the whole project in every worker
        # and merge all but one of those passes away. See #1250.
        it "leaves not-loaded-file injection to the merge step" do
          allow(described_class).to receive(:inject_unloaded_files).and_return([{}, Set.new])
          described_class.result
          expect(described_class).not_to have_received(:inject_unloaded_files)
        end

        it "stores the current coverage" do
          allow(SimpleCov::ResultMerger).to receive(:store_result)
          described_class.result
          expect(SimpleCov::ResultMerger).to have_received(:store_result).once
        end

        it "stores the current coverage before waiting for sibling processes" do
          calls = []
          allow(SimpleCov::ResultMerger).to receive(:store_result) { calls << :store }
          allow(described_class).to receive(:wait_for_other_processes) { calls << :wait }
          allow(SimpleCov::ResultMerger).to receive(:merged_result) do
            calls << :merge
            the_merged_result
          end

          described_class.result

          expect(calls).to eq(%i[store wait merge])
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

    context "with merging enabled in a process that does not own finalization" do
      before do
        allow(described_class).to receive_messages(merging: true, merge_finalization_owner?: false)
        allow(Coverage).to receive(:running?).and_return(true)
        allow(SimpleCov::ResultMerger).to receive(:store_result)
        allow(SimpleCov::ResultMerger).to receive(:merged_result)
        allow(described_class).to receive(:wait_for_other_processes)
      end

      it "stores and returns the worker result without waiting or merging" do
        result = described_class.result

        expect(result).to be_a(SimpleCov::Result)
        expect(SimpleCov::ResultMerger).to have_received(:store_result).with(result)
        expect(described_class).not_to have_received(:wait_for_other_processes)
        expect(SimpleCov::ResultMerger).not_to have_received(:merged_result)
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

  describe ".exit_status_from_exception", mutant_expression: "SimpleCov.exit_status_from_exception" do
    # A deliberate exit carries its own status, and a subclass of one is
    # still a deliberate exit.
    context "when a subclass of SystemExit has occurred" do
      it "returns that exit's status" do
        raise Class.new(SystemExit), 3
      rescue SystemExit
        expect(described_class.exit_status_from_exception).to eq(3)
      end
    end

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

  describe ".process_result", mutant_expression: "SimpleCov.process_result" do
    let(:result) { SimpleCov::Result.new({}) }

    # A run that passed becomes both the baseline the next run compares
    # against and a point in the recorded trend. A run that failed
    # becomes neither, so a red build cannot lower the bar.
    describe "what a run leaves behind" do
      before do
        allow(described_class).to receive(:write_last_run)
        allow(SimpleCov::History).to receive(:record)
      end

      it "records the run against itself and in the trend when it passed" do
        allow(described_class).to receive(:result_exit_status).and_return(SimpleCov::ExitCodes::SUCCESS)

        expect(described_class.process_result(result)).to eq(SimpleCov::ExitCodes::SUCCESS)
        expect(described_class).to have_received(:write_last_run).with(result)
        expect(SimpleCov::History).to have_received(:record).with(result)
      end

      it "records neither when it failed" do
        allow(described_class).to receive(:result_exit_status)
          .and_return(SimpleCov::ExitCodes::MINIMUM_COVERAGE)

        expect(described_class.process_result(result)).to eq(SimpleCov::ExitCodes::MINIMUM_COVERAGE)
        expect(described_class).not_to have_received(:write_last_run)
        expect(SimpleCov::History).not_to have_received(:record)
      end

      # Any non-success status, not merely the one the thresholds raise.
      it "records neither when the run ended in an exception" do
        allow(described_class).to receive(:result_exit_status).and_return(SimpleCov::ExitCodes::EXCEPTION)

        described_class.process_result(result)
        expect(described_class).not_to have_received(:write_last_run)
      end

      it "judges the result it was handed" do
        allow(described_class).to receive(:result_exit_status).and_return(SimpleCov::ExitCodes::SUCCESS)

        described_class.process_result(result)
        expect(described_class).to have_received(:result_exit_status).with(result)
      end
    end

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
          # The success path records the run for real, which would leave a
          # .history.json in the shared coverage path for later specs to find.
          allow(SimpleCov::History).to receive(:record)
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

  describe ".collate", mutant_expression: "SimpleCov.collate" do
    # What collating asks of its collaborators, rather than what they
    # produce, so the arguments it passes are visible.
    let(:collated) do
      JSON.parse(File.read(resultset_path)).transform_values { |v| v.reject { |k| k == "timestamp" } }
    end
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
    let(:resultset_folder) { File.dirname(resultset_path) }
    let(:resultset_path) { SimpleCov::ResultMerger.resultset_path }
    # A coverage folder of this block's own: collating reads every shard
    # it finds beside the resultset, and the suite's own folder is where
    # every other example leaves theirs.
    let(:coverage_folder) { Dir.mktmpdir("simplecov-collate-spec-") }
    let(:second_resultset) do
      {source_fixture("sample.rb") => {"lines" => [1, nil, 1, 1, nil, nil, 1, 1, nil, nil]}}
    end
    let(:first_resultset) do
      {source_fixture("sample.rb") => {"lines" => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil]}}
    end

    after { FileUtils.remove_entry(coverage_folder) }
    before { allow(described_class).to receive_messages(coverage_path: coverage_folder, coverage_dir: coverage_folder) }

    describe "the merge it asks for" do
      before do
        allow(SimpleCov::ParallelResultMerger).to receive(:merge_and_store).and_return(SimpleCov::Result.new({}))
        allow(described_class).to receive_messages(initial_setup: nil, run_exit_tasks!: nil)
      end

      it "refuses to collate nothing, saying why" do
        expect { described_class.collate([]) }
          .to raise_error(ArgumentError, "There are no reports to be merged")
        expect(SimpleCov::ParallelResultMerger).not_to have_received(:merge_and_store)
      end

      it "sets up with the profile it was given before merging anything" do
        described_class.collate(["a.json"], :rails)

        expect(described_class).to have_received(:initial_setup).with(:rails).ordered
        expect(SimpleCov::ParallelResultMerger).to have_received(:merge_and_store).ordered
      end

      it "sets up with no profile when none was named" do
        described_class.collate(["a.json"])
        expect(described_class).to have_received(:initial_setup).with(nil)
      end

      # A configuration block is the other way to set a collate up, so
      # it has to reach the setup along with the profile.
      it "hands the configuration block on to the setup" do
        block = proc { add_filter "x" }
        described_class.collate(["a.json"], &block)

        expect(described_class).to have_received(:initial_setup) do |_profile, &given|
          expect(given).to be(block)
        end
      end

      it "merges in one process when the environment says nothing" do
        with_env("SIMPLECOV_CONCURRENCY" => nil) do
          described_class.collate(["a.json"])
        end

        expect(SimpleCov::ParallelResultMerger).to have_received(:merge_and_store)
          .with(anything, hash_including(processes: 1))
      end

      # One process is the floor: a concurrency of nought or less would
      # merge nothing at all.
      it "merges with at least one process, however few were asked for" do
        described_class.collate(["a.json"], processes: 0)

        expect(SimpleCov::ParallelResultMerger).to have_received(:merge_and_store)
          .with("a.json", hash_including(processes: 1))
      end

      it "merges with as many processes as were asked for" do
        described_class.collate(["a.json"], processes: 4)

        expect(SimpleCov::ParallelResultMerger).to have_received(:merge_and_store)
          .with("a.json", hash_including(processes: 4))
      end

      it "ignores the merge timeout by default, and honours it when told to" do
        described_class.collate(["a.json"])
        expect(SimpleCov::ParallelResultMerger).to have_received(:merge_and_store)
          .with(anything, hash_including(ignore_timeout: true))

        described_class.collate(["a.json"], ignore_timeout: false)
        expect(SimpleCov::ParallelResultMerger).to have_received(:merge_and_store)
          .with(anything, hash_including(ignore_timeout: false))
      end

      # The flag says the result being reported came from a collate, and
      # it is put back whatever happens, including when the merge raises.
      it "marks the run as collating while the exit tasks run" do
        seen = nil
        allow(described_class).to receive(:run_exit_tasks!) { seen = described_class.collating_result? }

        described_class.collate(["a.json"])
        expect(seen).to be(true)
        expect(described_class.collating_result?).to be(false)
      end

      it "stops marking it even when the merge fails" do
        allow(SimpleCov::ParallelResultMerger).to receive(:merge_and_store).and_raise(RuntimeError)

        expect { described_class.collate(["a.json"]) }.to raise_error(RuntimeError)
        expect(described_class.collating_result?).to be(false)
      end
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

  describe ".collate across processes", mutant_expression: "SimpleCov.collate" do
    # As above: the shards this block collates are its own, in a folder
    # nothing else writes to.
    let(:coverage_folder) { Dir.mktmpdir("simplecov-collate-processes-spec-") }
    let(:resultset_path) { SimpleCov::ResultMerger.resultset_path }
    let(:resultset_folder) { File.dirname(resultset_path) }
    let(:collated) do
      JSON.parse(File.read(resultset_path)).transform_values { |data| data.reject { |key| key == "timestamp" } }
    end

    before { allow(described_class).to receive_messages(coverage_path: coverage_folder, coverage_dir: coverage_folder) }

    after { FileUtils.remove_entry(coverage_folder) }

    context "when no files to be merged" do
      it "shows an error message" do
        expect { described_class.collate([], processes: 2) }
          .to raise_error("There are no reports to be merged")
      end
    end

    context "when files to be merged" do
      before do
        allow(described_class).to receive(:run_exit_tasks!)
        5.times { |index| create_mergeable_report("result#{index}", index) }
      end

      after do
        described_class.clear_result
        FileUtils.rm Dir.glob("#{resultset_path}*")
      end

      it "produces the report a single-process collate produces" do
        expect(collate_with { |paths| described_class.collate paths, processes: 3 })
          .to eq(collate_with { |paths| described_class.collate paths })
        expect(described_class).to have_received(:run_exit_tasks!).twice
      end

      it "produces that report however many processes it is given" do
        reports = [1, 2, 4, 9].map do |processes|
          collate_with { |paths| described_class.collate paths, processes: processes }
        end

        expect(reports.uniq.size).to eq(1)
      end

      it "takes a process count below 1 as 1 rather than raising" do
        expect(collate_with { |paths| described_class.collate paths, processes: 0 })
          .to eq(collate_with { |paths| described_class.collate paths })
      end

      it "defaults the process count to SIMPLECOV_CONCURRENCY" do
        allow(SimpleCov::ParallelResultMerger).to receive(:absorb_results).and_call_original

        with_env("SIMPLECOV_CONCURRENCY" => "3") { collate_with { |paths| described_class.collate paths } }

        expect(SimpleCov::ParallelResultMerger).to have_received(:absorb_results)
          .with(anything, hash_including(processes: 3))
      end

      it "prefers an explicit process count over SIMPLECOV_CONCURRENCY" do
        allow(SimpleCov::ParallelResultMerger).to receive(:absorb_results).and_call_original

        with_env("SIMPLECOV_CONCURRENCY" => "3") do
          collate_with { |paths| described_class.collate paths, processes: 2 }
        end

        expect(SimpleCov::ParallelResultMerger).to have_received(:absorb_results)
          .with(anything, hash_including(processes: 2))
      end

      it "merges in this process when the fan-out cannot run" do
        serial = collate_with { |paths| described_class.collate paths }
        allow(SimpleCov::ParallelResultMerger).to receive(:absorb_results).and_return(nil)

        expect(collate_with { |paths| described_class.collate paths, processes: 3 }).to eq(serial)
      end

    private

      # Each shard covers `sample.rb` plus one file only it loaded, so the
      # merged table exercises both summing and union.
      def create_mergeable_report(name, index)
        coverage = {
          source_fixture("sample.rb") => {"lines" => [nil, 1, index, nil, nil, nil, 1, 1, nil, nil]},
          source_fixture("resultset#{index}.rb") => {"lines" => [1, index, nil, 1]}
        }
        result = SimpleCov::Result.new(coverage)
        result.command_name = name
        SimpleCov::ResultMerger.store_result(result)
        FileUtils.mv resultset_path, "#{resultset_path}#{name}.final"
      end

      # Collate the stored shards from a clean slate and return the resultset
      # that produced, so two strategies can be compared on equal terms —
      # `store_result` merges into whatever is already at `resultset_path`.
      def collate_with
        FileUtils.rm_f(resultset_path)
        described_class.clear_result
        yield Dir.glob("#{resultset_folder}/*.final", File::FNM_DOTMATCH)
        collated
      end
    end
  end

  # Normally wouldn't test private methods but just start has side effects that
  # cause errors so for time this is pragmatic (tm)
  describe ".start_coverage_measurement", mutant_expression: "SimpleCov.start_coverage_measurement" do
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

    # Measurement is started once. A process that already has Coverage
    # running joins it rather than restarting and losing what it holds.
    it "does not start measuring again where Coverage is already running" do
      allow(Coverage).to receive_messages(running?: true, start: nil)
      allow(described_class).to receive(:start_test_tracking)

      described_class.send(:start_coverage_measurement)
      expect(Coverage).not_to have_received(:start)
    end

    # Per-test attribution rides on the measurement, so it is started
    # either way: the process that joined an existing run still tracks.
    it "starts per-test tracking whether or not it started the measurement" do
      # The first half runs down the "not running" arm, so `Coverage.start`
      # has to be stubbed: whether this process really has measurement up
      # is a property of whatever ran before, and starting it twice raises.
      allow(Coverage).to receive(:start)
      allow(described_class).to receive(:start_test_tracking)

      described_class.send(:start_coverage_measurement)
      expect(described_class).to have_received(:start_test_tracking)

      allow(Coverage).to receive_messages(running?: true, start: nil)
      described_class.send(:start_coverage_measurement)
      expect(described_class).to have_received(:start_test_tracking).twice
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

    it "passes only the last requested line mode to Coverage.start" do
      allow(Coverage).to receive(:start)
      allow(described_class).to receive(:coverage_criterion_supported?).and_return(true)
      described_class.enable_coverage :oneshot_line
      described_class.enable_coverage :line

      described_class.send :start_coverage_measurement

      expect(Coverage).to have_received(:start).with({lines: true})
    end

    it "passes eval: true to Coverage.start when coverage_for_eval is enabled" do
      allow(Coverage).to receive(:start)
      allow(described_class).to receive(:coverage_for_eval_enabled?).and_return(true)
      described_class.send(:start_coverage_measurement)
      expect(Coverage).to have_received(:start).with(hash_including(eval: true))
    end

    it "omits `lines: true` when :line coverage has been disabled" do
      skip "branch coverage not supported on this engine" unless described_class.branch_coverage_supported?

      allow(Coverage).to receive(:start)
      previous = described_class.coverage_criteria.dup
      described_class.enable_coverage :branch
      described_class.disable_coverage :line
      described_class.send(:start_coverage_measurement)
      expect(Coverage).to have_received(:start).with(branches: true)
    ensure
      described_class.clear_coverage_criteria
      previous&.each { |c| described_class.enable_coverage(c) }
    end
  end

  describe ".current_run", mutant_expression: ["SimpleCov.current_run", "SimpleCov.clear_result"] do
    around do |example|
      previous = described_class.current_run
      example.run
      described_class.current_run = previous
    end

    it "begins a run of its own when the process has none" do
      described_class.current_run = nil

      expect(described_class.current_run).to be_a(SimpleCov::CurrentRun)
    end

    it "holds one run until a new one begins" do
      described_class.current_run = SimpleCov::CurrentRun.new
      held = described_class.current_run

      expect(held).to be_a(SimpleCov::CurrentRun)
      expect(described_class.current_run).to be(held)
    end

    it "reads and writes the run's state through the delegators" do
      described_class.current_run = SimpleCov::CurrentRun.new
      described_class.pid = 4242

      expect(described_class.pid).to eq(4242)
      expect(described_class.current_run.pid).to eq(4242)
      expect(described_class.result?).to be(false)
      expect(described_class).not_to be_forked_subprocess
    end

    it "forgets the run's result on clear_result, the way a fresh look requires" do
      described_class.current_run = SimpleCov::CurrentRun.new
      described_class.current_run.result = instance_double(SimpleCov::Result)

      described_class.clear_result

      expect(described_class.result?).to be_nil
    end
  end

  describe ".external_at_exit?", mutant_expression: "SimpleCov.external_at_exit?" do
    around do |example|
      previous = described_class.external_at_exit
      example.run
      described_class.external_at_exit = previous
    end

    it "answers false, not nil, when nobody claimed the at_exit" do
      described_class.external_at_exit = nil

      expect(described_class.external_at_exit?).to be(false)
    end

    it "answers a boolean rather than whatever was assigned" do
      described_class.external_at_exit = "the minitest plugin"

      expect(described_class.external_at_exit?).to be(true)
    end
  end

  describe ".coverage_statistics_key", mutant_expression: "SimpleCov.coverage_statistics_key" do
    it "folds oneshot lines into the line bucket, where ResultAdapter puts them" do
      expect(described_class.coverage_statistics_key(:oneshot_line)).to be(:line)
    end

    it "leaves every other criterion under its own name" do
      expect(described_class.coverage_statistics_key(:branch)).to be(:branch)
      expect(described_class.coverage_statistics_key(:method)).to be(:method)
      expect(described_class.coverage_statistics_key(:line)).to be(:line)
    end
  end

  describe ".minitest_autorun_pending?", mutant_expression: "SimpleCov.minitest_autorun_pending?" do
    it "is false where Minitest was never loaded" do
      hide_const("Minitest")

      expect(described_class.send(:minitest_autorun_pending?)).to be(false)
    end

    it "is false where a Minitest-like constant cannot be asked about after_run" do
      stub_const("Minitest", Module.new)

      expect(described_class.send(:minitest_autorun_pending?)).to be(false)
    end

    it "is false where the constant never armed autorun" do
      stub_const("Minitest", Class.new { def self.after_run; end })

      expect(described_class.send(:minitest_autorun_pending?)).to be(false)
    end

    it "is false where the constant carries autorun's mark but cannot be asked to defer" do
      impostor = Class.new
      impostor.class_variable_set(:@@installed_at_exit, true)
      stub_const("Minitest", impostor)

      expect(described_class.send(:minitest_autorun_pending?)).to be(false)
    end

    it "answers with what autorun recorded" do
      armed = Class.new { def self.after_run; end }
      armed.class_variable_set(:@@installed_at_exit, true)
      stub_const("Minitest", armed)

      expect(described_class.send(:minitest_autorun_pending?)).to be(true)
    end

    it "answers false where autorun recorded that it is not armed" do
      disarmed = Class.new { def self.after_run; end }
      disarmed.class_variable_set(:@@installed_at_exit, false)
      stub_const("Minitest", disarmed)

      expect(described_class.send(:minitest_autorun_pending?)).to be(false)
    end
  end

  describe ".defer_to_minitest_after_run", mutant_expression: "SimpleCov.defer_to_minitest_after_run" do
    around do |example|
      previous = described_class.external_at_exit
      example.run
      described_class.external_at_exit = previous
    end

    it "stands its own at_exit down and reports from Minitest.after_run instead" do
      blocks = []
      fake_minitest = Class.new
      fake_minitest.define_singleton_method(:after_run) { |&block| blocks << block }
      stub_const("Minitest", fake_minitest)
      described_class.external_at_exit = false
      allow(described_class).to receive(:at_exit_behavior)

      described_class.send(:defer_to_minitest_after_run)

      expect(described_class.external_at_exit?).to be(true)
      expect(blocks.size).to eq(1)
      blocks.each(&:call)
      expect(described_class).to have_received(:at_exit_behavior)
    end
  end

  describe ".warn_about_start_in_dot_simplecov",
           mutant_expression: "SimpleCov.warn_about_start_in_dot_simplecov" do
    around do |example|
      previous = described_class.instance_variable_get(:@dot_simplecov_start_warned)
      described_class.instance_variable_set(:@dot_simplecov_start_warned, nil)
      example.run
      described_class.instance_variable_set(:@dot_simplecov_start_warned, previous)
    end

    it "names the deprecation, the file, and where the call belongs instead" do
      stderr = capture_stderr { described_class.send(:warn_about_start_in_dot_simplecov) }

      expect(stderr).to include("[DEPRECATION]")
      expect(stderr).to include("`.simplecov`")
      expect(stderr).to include("spec_helper.rb")
      expect(stderr).to include("581")
    end

    it "says it once, however many times `.simplecov` calls start" do
      first  = capture_stderr { described_class.send(:warn_about_start_in_dot_simplecov) }
      second = capture_stderr { described_class.send(:warn_about_start_in_dot_simplecov) }

      expect(first).not_to be_empty
      expect(second).to be_empty
    end
  end

  describe ".monotonic_time", mutant_expression: "SimpleCov.monotonic_time" do
    it "reads the clock that cannot be set backwards under it" do
      allow(Process).to receive(:clock_gettime).and_return(123.5)

      expect(described_class.send(:monotonic_time)).to eq(123.5)
      expect(Process).to have_received(:clock_gettime).with(Process::CLOCK_MONOTONIC)
    end
  end

  describe ".round_coverage", mutant_expression: "SimpleCov.round_coverage" do
    it "rounds down rather than to nearest, so a shortfall is never rounded away" do
      expect(described_class.round_coverage(89.999)).to eq(89.99)
    end

    it "keeps two decimals of a value that already fits" do
      expect(described_class.round_coverage(90.12)).to eq(90.12)
    end
  end

  describe ".load_profile", mutant_expression: "SimpleCov.load_profile" do
    it "asks the profile registry for the profile it was named" do
      allow(described_class.profiles).to receive(:load)

      described_class.load_profile("rails")

      expect(described_class.profiles).to have_received(:load).with("rails")
    end
  end

  describe ".grouped_file_set", mutant_expression: "SimpleCov.grouped_file_set" do
    it "unions the files across every group, not just the first" do
      lib  = instance_double(SimpleCov::SourceFile, filename: "lib/foo.rb")
      test = instance_double(SimpleCov::SourceFile, filename: "test/foo.rb")

      expect(described_class.send(:grouped_file_set, {"Lib" => [lib], "Test" => [test]}))
        .to eq(Set[lib, test])
    end

    it "is empty when there are no groups" do
      expect(described_class.send(:grouped_file_set, {})).to eq(Set.new)
    end
  end

  describe ".filtered", mutant_expression: "SimpleCov.filtered" do
    let(:lib_file) do
      instance_double(SimpleCov::SourceFile, filename: "/abs/lib/foo.rb", project_filename: "lib/foo.rb")
    end
    let(:spec_file) do
      instance_double(SimpleCov::SourceFile, filename: "/abs/spec/foo.rb", project_filename: "spec/foo.rb")
    end

    around do |example|
      previous = described_class.filters
      described_class.filters = []
      example.run
      described_class.filters = previous
    end

    it "drops what a filter matches and keeps what it does not" do
      described_class.skip "spec"

      expect(described_class.filtered([lib_file, spec_file]).map(&:filename)).to eq(["/abs/lib/foo.rb"])
    end

    it "applies every filter, not only the first" do
      described_class.skip "spec"
      described_class.skip "lib"

      expect(described_class.filtered([lib_file, spec_file])).to be_empty
    end

    it "hands back a file list, which is what the formatters are given" do
      expect(described_class.filtered([lib_file])).to be_a(SimpleCov::FileList)
    end

    it "hands back a list that behaves like an array whatever it was given" do
      expect(described_class.filtered(Set[lib_file]).to_ary).to eq([lib_file])
    end

    it "leaves the collection it was handed alone" do
      described_class.skip "spec"
      files = [lib_file, spec_file]

      described_class.filtered(files)

      expect(files).to eq([lib_file, spec_file])
    end
  end

  describe ".collect_own_coverage", mutant_expression: "SimpleCov.collect_own_coverage" do
    it "collects nothing where measurement is not running" do
      allow(Coverage).to receive(:running?).and_return(false)
      allow(described_class).to receive(:process_coverage_result)

      described_class.send(:collect_own_coverage, standalone: true)

      expect(described_class).not_to have_received(:process_coverage_result)
    end

    it "collects nothing where the Coverage library was never loaded" do
      hide_const("Coverage")
      allow(described_class).to receive(:process_coverage_result)

      described_class.send(:collect_own_coverage, standalone: true)

      expect(described_class).not_to have_received(:process_coverage_result)
    end

    it "reports and injects when this slice is the final result" do
      allow(Coverage).to receive(:running?).and_return(true)
      allow(described_class).to receive(:process_coverage_result)

      described_class.send(:collect_own_coverage, standalone: true)

      expect(described_class)
        .to have_received(:process_coverage_result).with(report: true, inject_unloaded: true)
    end

    it "leaves both to the merged result when a merge follows" do
      allow(Coverage).to receive(:running?).and_return(true)
      allow(described_class).to receive(:process_coverage_result)

      described_class.send(:collect_own_coverage, standalone: false)

      expect(described_class)
        .to have_received(:process_coverage_result).with(report: false, inject_unloaded: false)
    end
  end

  describe ".tracked_file_paths", mutant_expression: "SimpleCov.tracked_file_paths" do
    it "discovers the globs under the root, minus what the path-only filters reject" do
      path_only = instance_double(SimpleCov::StringFilter, path_only?: true)
      content   = instance_double(SimpleCov::BlockFilter, path_only?: false)
      allow(described_class).to receive_messages(unloaded_file_discovery_globs: ["lib/**/*.rb"],
                                                 root: "/project", filters: [path_only, content])
      allow(SimpleCov::UnloadedFileInjector).to receive(:discover).and_return(Set.new)

      described_class.send(:tracked_file_paths)

      expect(SimpleCov::UnloadedFileInjector)
        .to have_received(:discover).with(["lib/**/*.rb"], root: "/project", reject: [path_only])
    end

    it "hands back what the injector discovered" do
      allow(described_class).to receive_messages(unloaded_file_discovery_globs: [], root: "/project", filters: [])
      allow(SimpleCov::UnloadedFileInjector).to receive(:discover).and_return(Set["/project/lib/foo.rb"])

      expect(described_class.send(:tracked_file_paths)).to eq(Set["/project/lib/foo.rb"])
    end
  end

  describe ".build_coverage_limits", mutant_expression: "SimpleCov.build_coverage_limits" do
    around do |example|
      previous = described_class.minimum_coverage
      example.run
      described_class.minimum_coverage(previous)
    end

    it "snapshots every limit under the name of the reader that supplies it" do
      limits = described_class.send(:build_coverage_limits)

      limits.class.members.each do |name|
        expect(limits.public_send(name)).to eq(described_class.public_send(name))
      end
    end

    it "reads the limits as they stand rather than as they were defined" do
      described_class.minimum_coverage(line: 42.5)

      expect(described_class.send(:build_coverage_limits).minimum_coverage).to eq(line: 42.5)
    end
  end

  describe ".result_exit_status", mutant_expression: "SimpleCov.result_exit_status" do
    it "asks the exit-code handling about this result against the limits as they stand" do
      result = instance_double(SimpleCov::Result)
      limits = instance_double(described_class.singleton_class::CoverageLimits)
      allow(described_class).to receive(:build_coverage_limits).and_return(limits)
      allow(SimpleCov::ExitCodes::ExitCodeHandling).to receive(:call).and_return(7)

      expect(described_class.result_exit_status(result)).to eq(7)
      expect(SimpleCov::ExitCodes::ExitCodeHandling)
        .to have_received(:call).with(result, coverage_limits: limits)
    end
  end

  describe ".existing_report_newer_than_us?",
           mutant_expression: "SimpleCov.existing_report_newer_than_us?" do
    it "is false where this process never recorded when it started" do
      allow(described_class).to receive(:process_start_time).and_return(nil)

      expect(described_class.send(:existing_report_newer_than_us?)).to be(false)
    end

    it "asks about the last-run file and the report stamp alike" do
      allow(described_class).to receive(:process_start_time).and_return(100)
      allow(File).to receive(:mtime).and_return(50)

      described_class.send(:existing_report_newer_than_us?)

      expect(File).to have_received(:mtime).with(SimpleCov::LastRun.last_run_path)
      expect(File).to have_received(:mtime).with(SimpleCov::ReportStamp.path)
    end

    it "is false where every report on disk predates this process" do
      allow(described_class).to receive(:process_start_time).and_return(100)
      allow(File).to receive(:mtime).and_return(50)

      expect(described_class.send(:existing_report_newer_than_us?)).to be(false)
    end

    it "is false where a report was written at the very moment this process started" do
      allow(described_class).to receive(:process_start_time).and_return(100)
      allow(File).to receive(:mtime).and_return(100)

      expect(described_class.send(:existing_report_newer_than_us?)).to be(false)
    end

    it "is true where the report stamp is the newer one" do
      allow(described_class).to receive(:process_start_time).and_return(100)
      allow(File).to receive(:mtime).with(SimpleCov::LastRun.last_run_path).and_return(50)
      allow(File).to receive(:mtime).with(SimpleCov::ReportStamp.path).and_return(150)

      expect(described_class.send(:existing_report_newer_than_us?)).to be(true)
    end

    it "is true where the last-run file is the newer one" do
      allow(described_class).to receive(:process_start_time).and_return(100)
      allow(File).to receive(:mtime).with(SimpleCov::LastRun.last_run_path).and_return(150)
      allow(File).to receive(:mtime).with(SimpleCov::ReportStamp.path).and_return(50)

      expect(described_class.send(:existing_report_newer_than_us?)).to be(true)
    end

    it "treats a file that vanished mid-exit as not newer" do
      allow(described_class).to receive(:process_start_time).and_return(100)
      allow(File).to receive(:mtime).and_raise(Errno::ENOENT)

      expect(described_class.send(:existing_report_newer_than_us?)).to be(false)
    end
  end

  describe ".warn_about_deferred_report", mutant_expression: "SimpleCov.warn_about_deferred_report" do
    it "says nothing where print_errors is off" do
      allow(described_class).to receive(:print_errors).and_return(false)

      expect(capture_stderr { described_class.send(:warn_about_deferred_report) }).to be_empty
    end

    it "explains what was skipped, where the report is, and why this happens" do
      allow(described_class).to receive(:print_errors).and_return(true)

      stderr = capture_stderr { described_class.send(:warn_about_deferred_report) }

      expect(stderr).to include("Skipping SimpleCov report")
      expect(stderr).to include(described_class.coverage_path)
      expect(stderr).to include("581")
    end

    it "colors the notice yellow, the shade it reserves for a run it did not spoil" do
      allow(described_class).to receive(:print_errors).and_return(true)
      allow(SimpleCov::Color).to receive(:colorize).and_return("colorized")

      capture_stderr { described_class.send(:warn_about_deferred_report) }

      expect(SimpleCov::Color)
        .to have_received(:colorize).with(/\ASkipping SimpleCov report /, :yellow)
    end
  end

  describe ".current_parallel_worker_count",
           mutant_expression: "SimpleCov.current_parallel_worker_count" do
    it "counts the workers that reported into this run, not every worker on record" do
      resultset = {"a" => {}}
      allow(SimpleCov::ResultMerger).to receive_messages(read_resultset: resultset,
                                                         worker_identities_for_run: %w[w1 w2 w3])
      allow(described_class).to receive_messages(run_id: "run-1", process_start_time: 99.5)

      expect(described_class.send(:current_parallel_worker_count)).to eq(3)
      expect(SimpleCov::ResultMerger)
        .to have_received(:worker_identities_for_run).with(resultset, "run-1", 99.5)
    end
  end

  describe ".resultset_count_settled?", mutant_expression: "SimpleCov.resultset_count_settled?" do
    it "is unsettled while the count is still climbing, and notes when it last moved" do
      allow(described_class).to receive(:monotonic_time).and_return(50.0)
      tracker = {count: 1, since: 10.0}

      expect(described_class.send(:resultset_count_settled?, tracker, 2)).to be(false)
      expect(tracker).to eq(count: 2, since: 50.0)
    end

    it "is unsettled at zero, however long nothing has arrived" do
      allow(described_class).to receive(:monotonic_time).and_return(1000.0)

      expect(described_class.send(:resultset_count_settled?, {count: 0, since: 0.0}, 0)).to be(false)
    end

    it "is unsettled until a steady count has held for the settle window" do
      allow(described_class).to receive(:monotonic_time).and_return(10.4)

      expect(described_class.send(:resultset_count_settled?, {count: 2, since: 10.0}, 2)).to be(false)
    end

    it "is settled once a positive count has held for the whole settle window" do
      allow(described_class).to receive(:monotonic_time).and_return(10.5)

      expect(described_class.send(:resultset_count_settled?, {count: 2, since: 10.0}, 2)).to be(true)
    end

    it "stays settled well past the window, rather than only at its edge" do
      allow(described_class).to receive(:monotonic_time).and_return(40.0)

      expect(described_class.send(:resultset_count_settled?, {count: 2, since: 10.0}, 2)).to be(true)
    end

    it "leaves the tracker alone when the count did not climb" do
      allow(described_class).to receive(:monotonic_time).and_return(10.5)
      tracker = {count: 2, since: 10.0}

      described_class.send(:resultset_count_settled?, tracker, 1)

      expect(tracker).to eq(count: 2, since: 10.0)
    end
  end

  describe ".parallel_wait_timed_out?", mutant_expression: "SimpleCov.parallel_wait_timed_out?" do
    it "has not timed out while the deadline is still ahead, and says nothing" do
      allow(described_class).to receive_messages(monotonic_time: 10.0, warn_about_incomplete_parallel_results: nil)

      expect(described_class.send(:parallel_wait_timed_out?, 20.0, 4, 1)).to be(false)
      expect(described_class).not_to have_received(:warn_about_incomplete_parallel_results)
    end

    it "has not timed out at the deadline itself" do
      allow(described_class).to receive_messages(monotonic_time: 20.0, warn_about_incomplete_parallel_results: nil)

      expect(described_class.send(:parallel_wait_timed_out?, 20.0, 4, 1)).to be(false)
    end

    it "has timed out past the deadline, and says how many of how many reported" do
      allow(described_class).to receive_messages(monotonic_time: 21.0, warn_about_incomplete_parallel_results: nil)

      expect(described_class.send(:parallel_wait_timed_out?, 20.0, 4, 1)).to be(true)
      expect(described_class).to have_received(:warn_about_incomplete_parallel_results).with(4, 1)
    end
  end

  describe ".warn_about_incomplete_parallel_results",
           mutant_expression: "SimpleCov.warn_about_incomplete_parallel_results" do
    it "says nothing where print_errors is off" do
      allow(described_class).to receive(:print_errors).and_return(false)

      expect(capture_stderr { described_class.send(:warn_about_incomplete_parallel_results, 4, 1) }).to be_empty
    end

    it "names how many of how many reported, how long it waited, and what to raise" do
      allow(described_class).to receive_messages(print_errors: true, parallel_wait_timeout: 30)

      stderr = capture_stderr { described_class.send(:warn_about_incomplete_parallel_results, 4, 1) }

      expect(stderr).to include("Only 1 of 4 parallel-test workers reported within 30s")
      expect(stderr).to include("totals are partial")
      expect(stderr).to include("SimpleCov.parallel_wait_timeout")
    end

    it "colors the notice yellow, the shade it reserves for a partial answer" do
      allow(described_class).to receive_messages(print_errors: true, parallel_wait_timeout: 30)
      allow(SimpleCov::Color).to receive(:colorize).and_return("colorized")

      capture_stderr { described_class.send(:warn_about_incomplete_parallel_results, 4, 1) }

      expect(SimpleCov::Color).to have_received(:colorize).with(/\AOnly 1 of 4 /, :yellow)
    end
  end
end
