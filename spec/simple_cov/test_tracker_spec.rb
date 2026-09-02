# frozen_string_literal: true

require "helper"
require "coverage"

RSpec.describe SimpleCov::TestTracker do
  subject(:tracker) { described_class.new(root_regex: /\A#{Regexp.escape(project_root + File::SEPARATOR)}/i) }

  def project_root = File.expand_path("/proj")

  def lib_file = File.join(project_root, "lib/thing.rb")

  def gem_file = File.expand_path("/gems/rspec/lib/rspec.rb")

  def stub_peeks(before, after)
    allow(Coverage).to receive(:peek_result).and_return(before, after)
  end

  it "refuses a granularity it does not know" do
    expect { described_class.new(granularity: :sentence) }
      .to raise_error(ArgumentError, "unknown granularity :sentence, expected one of [:test, :file]")
  end

  describe "#track" do
    context "with one line of one file grown" do
      let(:idle_file) { File.join(project_root, "lib/idle.rb") }

      before do
        stub_peeks(
          {lib_file => {lines: [1, 0, nil, 5]}, idle_file => {lines: [3]}},
          {lib_file => {lines: [2, 0, nil, 5]}, idle_file => {lines: [3]}}
        )

        tracker.track("spec/thing_spec.rb:1") { :ran }
      end

      it "attributes the grown line to the test" do
        expect(tracker.recorded_map.covering(lib_file, 1)).to eq(["spec/thing_spec.rb:1"])
      end

      it "attributes no line that never ran" do
        expect(tracker.recorded_map.covering(lib_file, 2)).to eq([])
      end

      it "attributes no line whose count stood still" do
        expect(tracker.recorded_map.covering(lib_file, 4)).to eq([])
      end

      it "attributes no line of a file the test never touched" do
        expect(tracker.recorded_map.covering(idle_file, 1)).to eq([])
      end
    end

    it "returns the block's value" do
      stub_peeks({}, {})

      expect(tracker.track("spec/thing_spec.rb:1") { :value }).to eq(:value)
    end

    context "when the test raises" do
      before { stub_peeks({lib_file => {lines: [0]}}, {lib_file => {lines: [1]}}) }

      it "lets the error through" do
        expect { tracker.track("spec/thing_spec.rb:1") { raise "boom" } }.to raise_error("boom")
      end

      it "records the failing test's lines on the way down" do
        suppress(RuntimeError) { tracker.track("spec/thing_spec.rb:1") { raise "boom" } }

        expect(tracker.recorded_map.covering(lib_file, 1)).to eq(["spec/thing_spec.rb:1"])
      end
    end

    it "skips files outside the project root" do
      stub_peeks({gem_file => {lines: [0]}}, {gem_file => {lines: [9]}})

      tracker.track("spec/thing_spec.rb:1") { :ran }

      expect(tracker.recorded_map.covering(gem_file, 1)).to eq([])
    end

    context "with a file the test itself loaded" do
      before do
        stub_peeks({}, {lib_file => {lines: [1, nil, 0]}})

        tracker.track("spec/thing_spec.rb:1") { :ran }
      end

      it "attributes every executed line to the test" do
        expect(tracker.recorded_map.covering(lib_file, 1)).to eq(["spec/thing_spec.rb:1"])
      end

      it "attributes no unexecuted line to the test" do
        expect(tracker.recorded_map.covering(lib_file, 3)).to eq([])
      end
    end

    context "with bare line arrays, the shape a foreign lines-only Coverage.start produces" do
      before do
        stub_peeks({lib_file => [0, 1]}, {lib_file => [1, 1]})

        tracker.track("spec/thing_spec.rb:1") { :ran }
      end

      it "attributes the grown line to the test" do
        expect(tracker.recorded_map.covering(lib_file, 1)).to eq(["spec/thing_spec.rb:1"])
      end

      it "attributes no line whose count stood still" do
        expect(tracker.recorded_map.covering(lib_file, 2)).to eq([])
      end
    end

    it "has nothing to diff for a file that carries no line data at all" do
      other_file = File.join(project_root, "lib/other.rb")
      stub_peeks({lib_file => {branches: {}}}, {lib_file => {branches: {}}, other_file => {methods: {}}})

      tracker.track("spec/thing_spec.rb:1") { :ran }

      expect(tracker.recorded_map.to_h["files"]).to eq({})
    end

    it "matches files with the report's own root matching by default, case differences included" do
      file = File.join(SimpleCov.root.upcase, "lib/thing.rb")
      default_tracker = described_class.new
      allow(Coverage).to receive(:peek_result).and_return({file => {lines: [0]}}, {file => {lines: [1]}})

      default_tracker.track("spec/thing_spec.rb:1") { :ran }

      expect(default_tracker.recorded_map.covering(file, 1)).to eq(["spec/thing_spec.rb:1"])
    end

    context "with a same-thread nested track" do
      before do
        allow(Coverage).to receive(:peek_result).and_return(
          {lib_file => {lines: [0, 0]}},
          {lib_file => {lines: [1, 0]}},
          {lib_file => {lines: [1, 1]}},
          {lib_file => {lines: [1, 1]}}
        )

        tracker.track("spec/outer_spec.rb:1") do
          tracker.track("spec/inner_spec.rb:2") { :ran }
        end
      end

      it "attributes a line only the outer test reached to it alone" do
        expect(tracker.recorded_map.covering(lib_file, 1)).to eq(["spec/outer_spec.rb:1"])
      end

      it "attributes a line the nested test reached to both tests" do
        expect(tracker.recorded_map.covering(lib_file, 2)).to eq(["spec/inner_spec.rb:2", "spec/outer_spec.rb:1"])
      end
    end
  end

  describe "segments" do
    context "with two tracks under different ids" do
      before do
        allow(Coverage).to receive(:peek_result).and_return(
          {lib_file => {lines: [0, 0, 0]}},
          {lib_file => {lines: [1, 0, 0]}},
          {lib_file => {lines: [1, 1, 1]}}
        )

        tracker.track("spec/first_spec.rb:1") { :ran }
        tracker.track("spec/second_spec.rb:2") { :ran }
      end

      it "takes one peek per boundary" do
        tracker.recorded_map

        expect(Coverage).to have_received(:peek_result).exactly(3).times
      end

      it "attributes the first segment to the first test" do
        expect(tracker.recorded_map.covering(lib_file, 1)).to eq(["spec/first_spec.rb:1"])
      end

      it "attributes the second segment to the second test" do
        expect(tracker.recorded_map.covering(lib_file, 2)).to eq(["spec/second_spec.rb:2"])
      end

      it "attributes the gap forward, to the test that followed it" do
        expect(tracker.recorded_map.covering(lib_file, 3)).to eq(["spec/second_spec.rb:2"])
      end
    end

    context "with one track and no flush yet" do
      before do
        allow(Coverage).to receive(:peek_result).and_return(
          {lib_file => {lines: [0]}},
          {lib_file => {lines: [1]}}
        )

        tracker.track("spec/first_spec.rb:1") { :ran }
      end

      it "defers recording to the boundary, so the raw map lags" do
        expect(tracker.map.covering(lib_file, 1)).to eq([])
      end

      it "records the segment at the flush" do
        expect(tracker.recorded_map.covering(lib_file, 1)).to eq(["spec/first_spec.rb:1"])
      end
    end

    context "with consecutive tracks of the same id" do
      before do
        allow(Coverage).to receive(:peek_result).and_return(
          {lib_file => {lines: [0, 0]}},
          {lib_file => {lines: [1, 1]}}
        )

        tracker.track("spec/first_spec.rb:1") { :ran }
        tracker.track("spec/first_spec.rb:1") { :ran }
        tracker.track("spec/first_spec.rb:1") { :ran }
      end

      it "takes no extra peeks" do
        tracker.recorded_map

        expect(Coverage).to have_received(:peek_result).exactly(2).times
      end

      it "keeps one segment open across them" do
        expect(tracker.recorded_map.covering(lib_file, 1)).to eq(["spec/first_spec.rb:1"])
      end
    end

    context "with a supplied closing snapshot, the stopped-Coverage exit path" do
      let(:closed_map) { tracker.recorded_map(closing: {lib_file => {lines: [1]}}) }

      before do
        allow(Coverage).to receive(:peek_result).and_return({lib_file => {lines: [0]}})

        tracker.track("spec/first_spec.rb:1") { :ran }
      end

      it "flushes without peeking again" do
        closed_map

        expect(Coverage).to have_received(:peek_result).once
      end

      it "attributes the snapshot's growth to the open segment" do
        expect(closed_map.covering(lib_file, 1)).to eq(["spec/first_spec.rb:1"])
      end
    end

    context "when flushed twice" do
      before do
        allow(Coverage).to receive(:peek_result).and_return({lib_file => {lines: [1]}})

        tracker.track("spec/first_spec.rb:1") { :ran }
      end

      it "flushes idempotently" do
        first = tracker.recorded_map.to_h

        expect(tracker.recorded_map.to_h).to eq(first)
      end

      it "takes no peek for the second flush" do
        2.times { tracker.recorded_map }

        expect(Coverage).to have_received(:peek_result).exactly(2).times
      end
    end
  end

  describe "file granularity", mutant_expression: ["SimpleCov::TestTracker*",
    "SimpleCov::TestTracker#track"] do
    subject(:tracker) do
      described_class.new(root_regex: /\A#{Regexp.escape(project_root + File::SEPARATOR)}/i, granularity: :file)
    end

    context "with three tracks across two test files" do
      before do
        allow(Coverage).to receive(:peek_result).and_return(
          {lib_file => {lines: [0, 0, 0]}},
          {lib_file => {lines: [1, 1, 0]}},
          {lib_file => {lines: [1, 1, 1]}}
        )

        tracker.track("spec/first_spec.rb:1") { :ran }
        tracker.track("spec/first_spec.rb:9") { :ran }
        tracker.track("spec/second_spec.rb:2") { :ran }
      end

      it "merges the tests of one file into one segment" do
        tracker.recorded_map

        expect(Coverage).to have_received(:peek_result).exactly(3).times
      end

      it "attributes the merged segment's first line to its test file" do
        expect(tracker.recorded_map.covering(lib_file, 1)).to eq(["spec/first_spec.rb"])
      end

      it "attributes the merged segment's second line to its test file" do
        expect(tracker.recorded_map.covering(lib_file, 2)).to eq(["spec/first_spec.rb"])
      end

      it "attributes the next segment to the other test file" do
        expect(tracker.recorded_map.covering(lib_file, 3)).to eq(["spec/second_spec.rb"])
      end

      it "lists one context per test file" do
        expect(tracker.recorded_map.contexts).to eq(["spec/first_spec.rb", "spec/second_spec.rb"])
      end
    end

    it "keeps an id it cannot truncate whole" do
      allow(Coverage).to receive(:peek_result).and_return({lib_file => {lines: [0]}}, {lib_file => {lines: [1]}})

      tracker.track("FakeNativeTest#object_id") { :ran }

      expect(tracker.recorded_map.contexts).to eq(["FakeNativeTest#object_id"])
    end

    {
      "a colon followed by something that is not a line" => "MyTest:setup",
      "an id that is only a line number" => "12"
    }.each do |description, id|
      it "keeps #{description} whole" do
        allow(Coverage).to receive(:peek_result).and_return({lib_file => {lines: [0]}}, {lib_file => {lines: [1]}})

        tracker.track(id) { :ran }

        expect(tracker.recorded_map.contexts).to eq([id])
      end
    end

    it "truncates a line number of any length" do
      allow(Coverage).to receive(:peek_result).and_return({lib_file => {lines: [0]}}, {lib_file => {lines: [1]}})

      tracker.track("spec/first_spec.rb:123") { :ran }

      expect(tracker.recorded_map.contexts).to eq(["spec/first_spec.rb"])
    end
  end

  describe "overlapping tracks across threads" do
    def overlap
      tracker.track("spec/outer_spec.rb:1") do
        Thread.new { tracker.track("spec/inner_spec.rb:2") { :inner } }.value
      end
    end

    before { allow(Coverage).to receive(:peek_result).and_return({}) }

    it "still runs every test" do
      expect(without_stderr { overlap }).to eq(:inner)
    end

    it "still runs a test once the recording is poisoned" do
      capture_stderr { overlap }

      expect(without_stderr { overlap }).to eq(:inner)
    end

    it "poisons the recording" do
      capture_stderr { overlap }

      expect(tracker).to be_poisoned
    end

    it "warns once, however many tracks overlap" do
      expect(overlapping_twice.scan("cannot be attributed").size).to eq(1)
    end

    def overlapping_twice
      capture_stderr do
        overlap
        overlap
      end
    end

    it "still runs a test tracked after poisoning" do
      capture_stderr { overlap }

      expect(tracker.track("spec/late_spec.rb:3") { :ran }).to eq(:ran)
    end

    it "stops sampling coverage once poisoned" do
      capture_stderr { overlap }
      calls_after_poisoning = 0
      allow(Coverage).to receive(:peek_result) { calls_after_poisoning += 1 }
      tracker.track("spec/late_spec.rb:3") { :ran }

      expect(calls_after_poisoning).to eq(0)
    end

    it "stays quiet when print_errors is off" do
      allow(SimpleCov).to receive(:print_errors).and_return(false)

      output = capture_stderr { overlap }

      expect(output).to be_empty
    end
  end

  describe "nested tracks in one thread" do
    context "with sequential nested tracks" do
      before do
        allow(Coverage).to receive(:peek_result).and_return({})

        tracker.track("spec/outer_spec.rb:1") do
          tracker.track("spec/first_inner_spec.rb:2") { :ran }
          tracker.track("spec/second_inner_spec.rb:3") { :ran }
        end
      end

      it "stays unpoisoned" do
        expect(tracker.poisoned?).to be(false)
      end

      it "keeps a recorded map" do
        expect(tracker.recorded_map).not_to be_nil
      end
    end
  end

  describe "the tracker's own bookkeeping" do
    it "takes the lock around both halves of a track" do
      allow(Coverage).to receive(:peek_result).and_return({})
      lock = tracker.instance_variable_get(:@lock)
      allow(lock).to receive(:synchronize).and_call_original

      tracker.track("spec/thing_spec.rb:1") { :ran }

      expect(lock).to have_received(:synchronize).twice
    end

    it "records nothing for a track another thread poisoned mid-flight" do
      allow(Coverage).to receive(:peek_result).and_return({})

      capture_stderr { poison_mid_flight }

      expect(tracker.map.contexts).to eq([])
    end

    def poison_mid_flight
      tracker.track("spec/outer_spec.rb:1") do
        tracker.track("spec/inner_spec.rb:2") do
          Thread.new { tracker.track("spec/other_spec.rb:3") { :ran } }.value
        end
      end
    end
  end

  describe "#recorded_map" do
    context "with a snapshot it is given" do
      let(:closed_map) { tracker.recorded_map(closing: {lib_file => {lines: [1, 0]}}) }

      before do
        allow(Coverage).to receive(:peek_result).and_return({lib_file => {lines: [0, 0]}})

        tracker.track("spec/thing_spec.rb:1") { :ran }
      end

      it "needs no peek of its own" do
        closed_map

        expect(Coverage).to have_received(:peek_result).once
      end

      it "closes the open segment against it" do
        expect(closed_map.covering(lib_file, 1)).to eq(["spec/thing_spec.rb:1"])
      end
    end

    it "is the map while attribution is trustworthy" do
      allow(Coverage).to receive(:peek_result).and_return({})

      expect(tracker.recorded_map).to be(tracker.map)
    end

    it "is nil once poisoned" do
      allow(Coverage).to receive(:peek_result).and_return({})

      capture_stderr { poison }

      expect(tracker.recorded_map).to be_nil
    end

    def poison
      tracker.track("spec/outer_spec.rb:1") do
        Thread.new { tracker.track("spec/inner_spec.rb:2") { :inner } }.value
      end
    end
  end

  describe ".install_rspec_hook" do
    around do |example|
      example.run
    ensure
      described_class.reset_rspec_hook!
    end

    let(:around_blocks) { [] }
    let(:fake_config) do
      config = instance_double(RSpec::Core::Configuration)
      allow(config).to receive(:around) { |&block| around_blocks << block }
      config
    end
    let(:fake_rspec) do
      rspec = class_double(RSpec)
      allow(rspec).to receive(:configure).and_yield(fake_config)
      rspec
    end

    context "with one example run through the installed hook" do
      let(:procsy) { instance_double(RSpec::Core::Example::Procsy, metadata: {location: "./spec/a_spec.rb:12"}) }

      before do
        described_class.install_rspec_hook(fake_rspec)
        allow(procsy).to receive(:run)
        allow(SimpleCov).to receive(:track_test).and_yield

        Object.new.instance_exec(procsy, &around_blocks.first)
      end

      it "wraps it in a track_test call named after its location" do
        expect(SimpleCov).to have_received(:track_test).with("spec/a_spec.rb:12")
      end

      it "runs it" do
        expect(procsy).to have_received(:run)
      end
    end

    context "when installed twice in one process" do
      let(:second_rspec) { class_double(RSpec) }

      before do
        allow(second_rspec).to receive(:configure)

        described_class.install_rspec_hook(fake_rspec)
        described_class.install_rspec_hook(second_rspec)
      end

      it "registers one around block" do
        expect(around_blocks.size).to eq(1)
      end

      it "leaves the second RSpec unconfigured" do
        expect(second_rspec).not_to have_received(:configure)
      end
    end

    it "finds the RSpec this process has when it is handed none" do
      allow(RSpec).to receive(:configure)

      described_class.install_rspec_hook

      expect(RSpec).to have_received(:configure)
    end

    it "does nothing without an RSpec to configure" do
      expect { described_class.install_rspec_hook(nil) }.not_to raise_error
    end

    it "leaves the real RSpec alone once the process-wide guard is set" do
      described_class.install_rspec_hook(fake_rspec)
      allow(RSpec).to receive(:configure)

      described_class.install_rspec_hook

      expect(RSpec).not_to have_received(:configure)
    end
  end

  describe ".install_minitest_hook" do
    let(:fake_test_case) do
      Class.new do
        def name
          "test_something"
        end

        def run
          :base_ran
        end

        def test_something
        end
      end
    end

    context "with the wrapper prepended" do
      before do
        described_class.install_minitest_hook(fake_test_case)
        allow(SimpleCov).to receive(:track_test).and_yield
      end

      it "keeps the base run's answer" do
        expect(fake_test_case.new.run).to eq(:base_ran)
      end

      it "tracks each run under the test's definition site" do
        fake_test_case.new.run

        expect(SimpleCov).to have_received(:track_test)
          .with(match(%r{\Aspec/simple_cov/test_tracker_spec\.rb:\d+\z}))
      end
    end

    it "installs only once per test case" do
      described_class.install_minitest_hook(fake_test_case)
      described_class.install_minitest_hook(fake_test_case)

      expect(fake_test_case.ancestors.count(SimpleCov::TestTracker::MinitestRun)).to eq(1)
    end

    it "does nothing when Minitest::Test is not loaded" do
      expect { described_class.install_minitest_hook }.not_to raise_error
    end

    it "finds Minitest::Test itself when it is loaded" do
      stub_const("Minitest::Test", fake_test_case)

      described_class.install_minitest_hook

      expect(fake_test_case.ancestors).to include(SimpleCov::TestTracker::MinitestRun)
    end
  end

  describe ".install_framework_hooks" do
    before do
      allow(described_class).to receive(:install_rspec_hook)
      allow(described_class).to receive(:install_minitest_hook_when_loaded)

      described_class.install_framework_hooks
    end

    it "wires up the RSpec integration" do
      expect(described_class).to have_received(:install_rspec_hook)
    end

    it "wires up the Minitest integration" do
      expect(described_class).to have_received(:install_minitest_hook_when_loaded)
    end
  end

  describe ".install_minitest_hook_when_loaded" do
    let(:root) { Module.new }
    let(:test_case) { Class.new }

    def wrapped?(klass)
      klass.ancestors.include?(SimpleCov::TestTracker::MinitestRun)
    end

    def load_minitest_test(host, klass)
      minitest = Module.new
      minitest.const_set(:Test, klass)
      host.const_set(:Minitest, minitest)
    end

    it "installs immediately when Minitest::Test is already loaded" do
      load_minitest_test(root, test_case)

      described_class.install_minitest_hook_when_loaded(root)

      expect(wrapped?(test_case)).to be true
    end

    context "when only Minitest is loaded" do
      let(:minitest) { Module.new }

      before do
        root.const_set(:Minitest, minitest)

        described_class.install_minitest_hook_when_loaded(root)
      end

      it "waits for Minitest::Test" do
        expect(wrapped?(test_case)).to be false
      end

      it "wraps Minitest::Test once it arrives, past another constant" do
        minitest.const_set(:Other, Class.new)
        minitest.const_set(:Test, test_case)

        expect(wrapped?(test_case)).to be true
      end
    end

    context "when nothing of Minitest is loaded" do
      let(:minitest) { Module.new }

      before do
        described_class.install_minitest_hook_when_loaded(root)

        root.const_set(:SomethingElse, Module.new)
        root.const_set(:Minitest, minitest)
      end

      it "waits for Minitest::Test" do
        expect(wrapped?(test_case)).to be false
      end

      it "wraps Minitest::Test once it arrives" do
        minitest.const_set(:Test, test_case)

        expect(wrapped?(test_case)).to be true
      end
    end

    it "arms no watch when Minitest::Test is already there" do
      load_minitest_test(root, test_case)
      allow(SimpleCov::TestTracker::ConstantWatch).to receive(:new).and_call_original

      described_class.install_minitest_hook_when_loaded(root)

      expect(SimpleCov::TestTracker::ConstantWatch).not_to have_received(:new)
    end

    it "arms one watch when Minitest is there without its Test" do
      root.const_set(:Minitest, Module.new)
      allow(SimpleCov::TestTracker::ConstantWatch).to receive(:new).and_call_original

      described_class.install_minitest_hook_when_loaded(root)

      expect(SimpleCov::TestTracker::ConstantWatch).to have_received(:new).once
    end

    it "watches Object when it is handed no root" do
      watch = instance_double(SimpleCov::TestTracker::ConstantWatch, attach: nil)
      allow(described_class).to receive(:loaded_const).and_return(nil)
      allow(SimpleCov::TestTracker::ConstantWatch).to receive(:new).and_return(watch)

      described_class.install_minitest_hook_when_loaded

      expect(watch).to have_received(:attach).with(equal(Object))
    end

    context "when an autoload declares Minitest after the watch is armed" do
      before do
        described_class.install_minitest_hook_when_loaded(root)
        allow(SimpleCov::TestTracker::ConstantWatch).to receive(:new).and_call_original

        root.autoload(:Minitest, "some/nonexistent/minitest")
      end

      it "never forces the autoload to resolve" do
        expect(root.autoload?(:Minitest)).not_to be_nil
      end

      it "arms no further watch" do
        expect(SimpleCov::TestTracker::ConstantWatch).not_to have_received(:new)
      end
    end
  end

  describe SimpleCov::TestTracker::ConstantWatch do
    it "answers itself when attached, so a watch can be armed in one breath" do
      watch = described_class.new(:Target) { :never }

      expect(watch.attach(Module.new)).to be(watch)
    end

    it "does not run its callback while being built" do
      ran = false

      described_class.new(:Target) { ran = true }

      expect(ran).to be(false)
    end

    context "with a host that keeps a const_added of its own" do
      let(:calls) { [] }
      let(:host) { module_recording_into(calls) }
      let(:watch) { described_class.new(:Target) { calls << [:watch] } }

      before { watch.attach(host) }

      it "runs its callback exactly once, keeping the host's const_added chain intact" do
        host.const_set(:Target, 1)
        watch.notice(:Target)
        host.const_set(:Other, 2)

        expect(calls).to eq([%i[host Target], [:watch], %i[host Other]])
      end
    end

    def module_recording_into(calls)
      Module.new.tap do |host|
        host.singleton_class.define_method(:const_added) { |name| calls << [:host, name] }
      end
    end
  end

  describe SimpleCov::TestTracker::Delta do
    subject(:delta) { described_class.new(root_regex: /\A#{Regexp.escape("/app")}/) }

    let(:walker) { described_class.new(root_regex: /\A#{Regexp.escape("/app")}/) }

    def lines(counts) = {lines: counts}

    it "sets a bit for each line whose count grew, lowest line as the lowest bit" do
      before = {"/app/a.rb" => lines([1, 0, nil, 2])}
      after = {"/app/a.rb" => lines([1, 1, nil, 5])}

      expect(delta.call(before, after)).to eq("/app/a.rb" => 0b1010)
    end

    it "leaves out a file no line of which grew" do
      unchanged = {"/app/a.rb" => lines([1, 2, 3])}

      expect(delta.call(unchanged, unchanged)).to eq({})
    end

    it "claims every executed line of a file the test loaded itself" do
      after = {"/app/a.rb" => lines([1, 0, nil, 3])}

      expect(delta.call({}, after)).to eq("/app/a.rb" => 0b1001)
    end

    it "ignores files outside the root" do
      before = {"/elsewhere/a.rb" => lines([0])}
      after = {"/elsewhere/a.rb" => lines([1])}

      expect(delta.call(before, after)).to eq({})
    end

    it "keeps reading past a file outside the root" do
      before = {"/elsewhere/a.rb" => lines([0]), "/app/a.rb" => lines([0])}
      after = {"/elsewhere/a.rb" => lines([1]), "/app/a.rb" => lines([1])}

      expect(delta.call(before, after)).to eq("/app/a.rb" => 0b1)
    end

    it "asks the root regex about a file once, however many tests it appears in" do
      asked = []
      memoizing = described_class.new(root_regex: regex_recording_into(asked))

      2.times { memoizing.call({}, {"/app/a.rb" => lines([1])}) }

      expect(asked).to eq(["/app/a.rb"])
    end

    it "does not walk the lines of a file nothing touched" do
      before = {"/app/a.rb" => lines([1, 2, 3])}
      after = {"/app/a.rb" => lines([1, 2, 3])}
      allow(walker).to receive(:grew?).and_call_original

      walker.call(before, after)

      expect(walker).not_to have_received(:grew?)
    end

    it "reads a bare line array as per-file coverage" do
      expect(delta.call({"/app/a.rb" => [0]}, {"/app/a.rb" => [1]})).to eq("/app/a.rb" => 0b1)
    end

    it "reads a lines-keyed hash as per-file coverage" do
      expect(delta.call({"/app/a.rb" => lines([0])}, {"/app/a.rb" => lines([1])})).to eq("/app/a.rb" => 0b1)
    end

    def regex_recording_into(asked)
      Object.new.tap do |regex|
        regex.define_singleton_method(:match?) do |path|
          asked << path
          path.start_with?("/app")
        end
      end
    end

    it "finds nothing to diff when the run measured no lines at all" do
      expect(delta.call({"/app/a.rb" => {branches: {}}}, {"/app/a.rb" => {branches: {}}})).to eq({})
    end

    it "treats a line that stopped being executable as not grown" do
      expect(delta.call({"/app/a.rb" => lines([1, 1])}, {"/app/a.rb" => lines([1, nil])})).to eq({})
    end

    it "treats a count that fell as not grown" do
      expect(delta.call({"/app/a.rb" => lines([5])}, {"/app/a.rb" => lines([2])})).to eq({})
    end

    it "handles a file whose lines are all zero without producing an entry" do
      expect(delta.call({}, {"/app/a.rb" => lines([0, 0])})).to eq({})
    end

    it "handles a file with no lines at all" do
      expect(delta.call({}, {"/app/a.rb" => lines([])})).to eq({})
    end

    it "reads a shorter earlier peek as having nothing on the lines it lacks" do
      expect(delta.call({"/app/a.rb" => lines([1])}, {"/app/a.rb" => lines([1, 2])}))
        .to eq("/app/a.rb" => 0b10)
    end

    it "finds nothing to diff when only the earlier peek measured lines" do
      expect(delta.call({"/app/a.rb" => lines([1])}, {"/app/a.rb" => {branches: {}}})).to eq({})
    end
  end

  describe ".loaded_const" do
    def module_including(ancestor)
      Module.new.tap { |host| host.include(ancestor) }
    end

    it "ignores a constant that belongs to an ancestor" do
      ancestor = Module.new
      ancestor.const_set(:Target, Class.new)

      expect(described_class.loaded_const(module_including(ancestor), :Target)).to be_nil
    end

    it "leaves a constant that is only declared for autoload alone" do
      host = Module.new
      host.autoload(:Target, "some/nonexistent/target")

      expect(described_class.loaded_const(host, :Target)).to be_nil
    end

    it "answers a constant of its own that an ancestor merely autoloads" do
      ancestor = Module.new
      ancestor.autoload(:Target, "some/nonexistent/target")
      host = module_including(ancestor)
      host.const_set(:Target, :loaded)

      expect(described_class.loaded_const(host, :Target)).to eq(:loaded)
    end
  end

  describe ".minitest_test_id" do
    let(:located_test) do
      Class.new do
        def name = "test_example"

        def test_example
        end
      end
    end

    let(:private_test) do
      Class.new do
        def name = "test_hidden"

        private

        def test_hidden
        end
      end
    end

    it "names a test by where its method is defined, relative to the root" do
      stub_const("FakeLocatedTest", located_test)
      _, line = located_test.instance_method(:test_example).source_location

      expect(described_class.minitest_test_id(located_test.new)).to eq("spec/simple_cov/test_tracker_spec.rb:#{line}")
    end

    it "keeps the whole path of a test defined outside the project" do
      # rubocop:disable Style/EvalWithLocation
      klass = Class.new
      klass.class_eval("def name = \"test_outside\"\n\ndef test_outside; end\n", "/outside/a_test.rb", 1)
      # rubocop:enable Style/EvalWithLocation

      expect(described_class.minitest_test_id(klass.new)).to eq("/outside/a_test.rb:3")
    end

    it "names a test method the runner kept private" do
      stub_const("FakePrivateTest", private_test)
      _, line = private_test.instance_method(:test_hidden).source_location

      expect(described_class.minitest_test_id(private_test.new)).to eq("spec/simple_cov/test_tracker_spec.rb:#{line}")
    end

    it "falls back to Class#method for a test method with no source location" do
      test = Class.new { def name = "object_id" }.new
      stub_const("FakeNativeTest", test.class)

      expect(described_class.minitest_test_id(test)).to eq("FakeNativeTest#object_id")
    end

    it "falls back the same way when the named method does not exist" do
      test = Class.new { def name = "test_missing" }.new
      stub_const("FakeBrokenTest", test.class)

      expect(described_class.minitest_test_id(test)).to eq("FakeBrokenTest#test_missing")
    end
  end

  describe SimpleCov::TestTracker::Accessors do
    around do |example|
      example.run
    ensure
      SimpleCov.remove_instance_variable(:@test_tracker) if SimpleCov.instance_variable_defined?(:@test_tracker)
      SimpleCov.track_tests(false)
    end

    describe "#track_test" do
      it "has no tracker to delegate to" do
        expect(SimpleCov.test_tracker).to be_nil
      end

      it "just runs the block when no tracker is live" do
        expect(SimpleCov.track_test("spec/a_spec.rb:1") { :ran }).to eq(:ran)
      end

      context "with a live tracker" do
        let(:live_tracker) { instance_double(SimpleCov::TestTracker) }

        before do
          allow(live_tracker).to receive(:track).with("spec/a_spec.rb:1").and_yield
          SimpleCov.instance_variable_set(:@test_tracker, live_tracker)
        end

        it "answers the block's value" do
          expect(SimpleCov.track_test("spec/a_spec.rb:1") { :ran }).to eq(:ran)
        end

        it "delegates to it" do
          SimpleCov.track_test("spec/a_spec.rb:1") { :ran }

          expect(live_tracker).to have_received(:track).with("spec/a_spec.rb:1")
        end
      end
    end

    describe "#start_test_tracking" do
      before { allow(SimpleCov::TestTracker).to receive(:install_framework_hooks) }

      it "builds no tracker while track_tests is off" do
        SimpleCov.start_test_tracking

        expect(SimpleCov.test_tracker).to be_nil
      end

      it "installs no framework hooks while track_tests is off" do
        SimpleCov.start_test_tracking

        expect(SimpleCov::TestTracker).not_to have_received(:install_framework_hooks)
      end

      context "when track_tests is on" do
        before do
          SimpleCov.track_tests

          SimpleCov.start_test_tracking
        end

        it "builds the tracker" do
          expect(SimpleCov.test_tracker).to be_a(SimpleCov::TestTracker)
        end

        it "installs the framework hooks" do
          expect(SimpleCov::TestTracker).to have_received(:install_framework_hooks)
        end
      end

      it "refuses to start tracking a run that cannot produce deltas" do
        SimpleCov.track_tests
        allow(SimpleCov).to receive(:coverage_criterion_enabled?).with(:line).and_return(false)

        expect { SimpleCov.start_test_tracking }.to raise_error(SimpleCov::ConfigurationError, /track_tests/)
      end

      it "builds the tracker at the configured granularity" do
        SimpleCov.track_tests(granularity: :file)

        SimpleCov.start_test_tracking

        expect(SimpleCov.test_tracker.instance_variable_get(:@granularity)).to eq(:file)
      end

      context "when tracking restarts" do
        before do
          SimpleCov.track_tests
          SimpleCov.start_test_tracking
        end

        it "keeps the tracker, and its recordings, across the restart" do
          first = SimpleCov.test_tracker

          SimpleCov.start_test_tracking

          expect(SimpleCov.test_tracker).to be(first)
        end

        it "wires the framework hooks only once" do
          SimpleCov.start_test_tracking

          expect(SimpleCov::TestTracker).to have_received(:install_framework_hooks).once
        end
      end
    end
  end
end
