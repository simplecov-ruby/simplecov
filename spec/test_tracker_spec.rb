# frozen_string_literal: true

require "helper"
require "coverage"

RSpec.describe SimpleCov::TestTracker do
  subject(:tracker) { described_class.new(root_regex: /\A#{Regexp.escape(project_root + File::SEPARATOR)}/i) }

  # Expanded rather than written literally: on Windows an absolute path
  # carries a drive, and `covering` resolves its argument through
  # `File.expand_path`, so a literal `/proj` would never match its own
  # lookup there.
  let(:project_root) { File.expand_path("/proj") }
  let(:lib_file) { File.join(project_root, "lib/thing.rb") }
  let(:gem_file) { File.expand_path("/gems/rspec/lib/rspec.rb") }

  def stub_peeks(before, after)
    allow(Coverage).to receive(:peek_result).and_return(before, after)
  end

  describe "#track" do
    it "attributes the lines whose count grew, and only those, to the test" do
      idle_file = File.join(project_root, "lib/idle.rb")
      stub_peeks(
        {lib_file => {lines: [1, 0, nil, 5]}, idle_file => {lines: [3]}},
        {lib_file => {lines: [2, 0, nil, 5]}, idle_file => {lines: [3]}}
      )

      tracker.track("spec/thing_spec.rb:1") { :ran }

      expect(tracker.map.covering(lib_file, 1)).to eq(["spec/thing_spec.rb:1"])
      expect(tracker.map.covering(lib_file, 2)).to eq([])
      expect(tracker.map.covering(lib_file, 4)).to eq([])
      expect(tracker.map.covering(idle_file, 1)).to eq([])
    end

    it "returns the block's value" do
      stub_peeks({}, {})

      expect(tracker.track("spec/thing_spec.rb:1") { :value }).to eq(:value)
    end

    it "records a failing test's lines on the way down" do
      stub_peeks(
        {lib_file => {lines: [0]}},
        {lib_file => {lines: [1]}}
      )

      expect { tracker.track("spec/thing_spec.rb:1") { raise "boom" } }.to raise_error("boom")
      expect(tracker.map.covering(lib_file, 1)).to eq(["spec/thing_spec.rb:1"])
    end

    it "skips files outside the project root" do
      stub_peeks(
        {gem_file => {lines: [0]}},
        {gem_file => {lines: [9]}}
      )

      tracker.track("spec/thing_spec.rb:1") { :ran }

      expect(tracker.map.covering(gem_file, 1)).to eq([])
    end

    it "attributes every executed line of a file the test itself loaded" do
      stub_peeks(
        {},
        {lib_file => {lines: [1, nil, 0]}}
      )

      tracker.track("spec/thing_spec.rb:1") { :ran }

      expect(tracker.map.covering(lib_file, 1)).to eq(["spec/thing_spec.rb:1"])
      expect(tracker.map.covering(lib_file, 3)).to eq([])
    end

    it "reads bare line arrays, the shape a foreign lines-only Coverage.start produces" do
      stub_peeks(
        {lib_file => [0, 1]},
        {lib_file => [1, 1]}
      )

      tracker.track("spec/thing_spec.rb:1") { :ran }

      expect(tracker.map.covering(lib_file, 1)).to eq(["spec/thing_spec.rb:1"])
      expect(tracker.map.covering(lib_file, 2)).to eq([])
    end

    it "has nothing to diff for a file that carries no line data at all" do
      stub_peeks(
        {lib_file => {branches: {}}},
        {lib_file => {branches: {}}, File.join(project_root, "lib/other.rb") => {methods: {}}}
      )

      tracker.track("spec/thing_spec.rb:1") { :ran }

      expect(tracker.map.to_h["files"]).to eq({})
    end

    it "matches files with the report's own root matching by default, case differences included" do
      file = File.join(SimpleCov.root.upcase, "lib/thing.rb")
      default_tracker = described_class.new
      allow(Coverage).to receive(:peek_result).and_return({file => {lines: [0]}}, {file => {lines: [1]}})

      default_tracker.track("spec/thing_spec.rb:1") { :ran }

      expect(default_tracker.map.covering(file, 1)).to eq(["spec/thing_spec.rb:1"])
    end

    it "attributes a same-thread nested track to both tests" do
      allow(Coverage).to receive(:peek_result).and_return(
        {lib_file => {lines: [0, 0]}}, # outer before
        {lib_file => {lines: [1, 0]}}, # inner before
        {lib_file => {lines: [1, 1]}}, # inner after
        {lib_file => {lines: [1, 1]}}  # outer after
      )

      tracker.track("spec/outer_spec.rb:1") do
        tracker.track("spec/inner_spec.rb:2") { :ran }
      end

      expect(tracker.map.covering(lib_file, 1)).to eq(["spec/outer_spec.rb:1"])
      expect(tracker.map.covering(lib_file, 2)).to eq(["spec/inner_spec.rb:2", "spec/outer_spec.rb:1"])
    end
  end

  # Coverage's counters are process-global: two tests running at once in
  # different threads cannot be told apart, so the recording shuts off
  # rather than misattribute lines.
  describe "overlapping tracks across threads" do
    def overlap
      tracker.track("spec/outer_spec.rb:1") do
        Thread.new { tracker.track("spec/inner_spec.rb:2") { :inner } }.value
      end
    end

    before { allow(Coverage).to receive(:peek_result).and_return({}) }

    it "poisons the recording, warns once, and still runs every test" do
      output = capture_stderr do
        expect(overlap).to eq(:inner)
        expect(overlap).to eq(:inner)
      end

      expect(tracker).to be_poisoned
      expect(output.scan("cannot be attributed").size).to eq(1)
    end

    it "stops sampling coverage once poisoned" do
      capture_stderr { overlap }
      calls_after_poisoning = 0
      allow(Coverage).to receive(:peek_result) { calls_after_poisoning += 1 }

      expect(tracker.track("spec/late_spec.rb:3") { :ran }).to eq(:ran)
      expect(calls_after_poisoning).to eq(0)
    end

    it "stays quiet when print_errors is off" do
      allow(SimpleCov).to receive(:print_errors).and_return(false)

      output = capture_stderr { overlap }

      expect(output).to be_empty
    end
  end

  describe "#recorded_map" do
    it "is the map while attribution is trustworthy, and nil once poisoned" do
      allow(Coverage).to receive(:peek_result).and_return({})

      expect(tracker.recorded_map).to be(tracker.map)

      capture_stderr do
        tracker.track("spec/outer_spec.rb:1") do
          Thread.new { tracker.track("spec/inner_spec.rb:2") { :inner } }.value
        end
      end

      expect(tracker.recorded_map).to be_nil
    end
  end

  describe ".install_rspec_hook" do
    around do |example|
      example.run
    ensure
      described_class.reset_rspec_hook!
    end

    # Stand-ins with the sliver of RSpec's surface the hook uses.
    let(:around_blocks) { [] }
    let(:fake_config) do
      config = double("RSpec configuration") # rubocop:disable RSpec/VerifiedDoubles
      allow(config).to receive(:around) { |&block| around_blocks << block }
      config
    end
    let(:fake_rspec) do
      rspec = double("RSpec") # rubocop:disable RSpec/VerifiedDoubles
      allow(rspec).to receive(:configure).and_yield(fake_config)
      rspec
    end

    it "wraps each example in a track_test call named after its location" do
      described_class.install_rspec_hook(fake_rspec)
      example = instance_double(RSpec::Core::Example::Procsy, metadata: {location: "./spec/a_spec.rb:12"})
      allow(example).to receive(:run)
      allow(SimpleCov).to receive(:track_test).and_yield

      around_blocks.first.call(example)

      expect(SimpleCov).to have_received(:track_test).with("spec/a_spec.rb:12")
      expect(example).to have_received(:run)
    end

    it "installs once per process" do
      second = double("RSpec") # rubocop:disable RSpec/VerifiedDoubles
      allow(second).to receive(:configure)

      described_class.install_rspec_hook(fake_rspec)
      described_class.install_rspec_hook(second)

      expect(around_blocks.size).to eq(1)
      expect(second).not_to have_received(:configure)
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

        def test_something; end
      end
    end

    it "prepends the wrapper so each run is tracked under the test's definition site" do
      described_class.install_minitest_hook(fake_test_case)
      allow(SimpleCov).to receive(:track_test).and_yield

      expect(fake_test_case.new.run).to eq(:base_ran)
      expect(SimpleCov).to have_received(:track_test)
        .with(match(%r{\Aspec/test_tracker_spec\.rb:\d+\z}))
    end

    it "installs only once per test case" do
      described_class.install_minitest_hook(fake_test_case)
      described_class.install_minitest_hook(fake_test_case)

      expect(fake_test_case.ancestors.count(SimpleCov::TestTracker::MinitestRun)).to eq(1)
    end

    it "finds Minitest::Test itself when loaded, and does nothing when it is not" do
      expect { described_class.install_minitest_hook }.not_to raise_error

      stub_const("Minitest::Test", fake_test_case)
      described_class.install_minitest_hook

      expect(fake_test_case.ancestors).to include(SimpleCov::TestTracker::MinitestRun)
    end
  end

  describe ".install_framework_hooks" do
    it "wires up both framework integrations" do
      allow(described_class).to receive(:install_rspec_hook)
      allow(described_class).to receive(:install_minitest_hook_when_loaded)

      described_class.install_framework_hooks

      expect(described_class).to have_received(:install_rspec_hook)
      expect(described_class).to have_received(:install_minitest_hook_when_loaded)
    end
  end

  # The deferred installs cover minitest 6, whose autorun no longer
  # discovers plugins: under the canonical helper ordering (SimpleCov
  # first, minitest after) nothing of Minitest exists to hook into yet, so
  # a one-shot `const_added` watch installs the wrapper the moment
  # `Minitest::Test` is defined. A stand-in root module plays Object.
  describe ".install_minitest_hook_when_loaded" do
    let(:root) { Module.new }
    let(:test_case) { Class.new }

    def wrapped?(klass)
      klass.ancestors.include?(SimpleCov::TestTracker::MinitestRun)
    end

    it "installs immediately when Minitest::Test is already loaded" do
      minitest = Module.new
      minitest.const_set(:Test, test_case)
      root.const_set(:Minitest, minitest)

      described_class.install_minitest_hook_when_loaded(root)

      expect(wrapped?(test_case)).to be true
    end

    it "waits for Minitest::Test when only Minitest is loaded" do
      minitest = Module.new
      root.const_set(:Minitest, minitest)

      described_class.install_minitest_hook_when_loaded(root)
      expect(wrapped?(test_case)).to be false

      minitest.const_set(:Other, Class.new)
      minitest.const_set(:Test, test_case)

      expect(wrapped?(test_case)).to be true
    end

    it "waits for Minitest itself when nothing of it is loaded" do
      described_class.install_minitest_hook_when_loaded(root)

      root.const_set(:SomethingElse, Module.new)
      minitest = Module.new
      root.const_set(:Minitest, minitest)
      expect(wrapped?(test_case)).to be false

      minitest.const_set(:Test, test_case)

      expect(wrapped?(test_case)).to be true
    end

    # const_added fires when an autoload is declared, before anything is
    # loaded — and installing a coverage hook must never be what requires
    # a test framework, so a declared-not-loaded Minitest is left alone.
    it "never forces an autoload to resolve" do
      described_class.install_minitest_hook_when_loaded(root)

      root.autoload(:Minitest, "some/nonexistent/minitest")

      expect(root.autoload?(:Minitest)).not_to be_nil
    end
  end

  describe SimpleCov::TestTracker::ConstantWatch do
    it "runs its callback exactly once, keeping the host's const_added chain intact" do
      host = Module.new
      calls = []
      host.singleton_class.define_method(:const_added) { |name| calls << [:host, name] }
      watch = described_class.new(:Target) { calls << [:watch] }
      watch.attach(host)

      host.const_set(:Target, 1)
      watch.notice(:Target)
      host.const_set(:Other, 2)

      expect(calls).to eq([%i[host Target], [:watch], %i[host Other]])
    end
  end

  describe ".minitest_test_id" do
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
      # Remove rather than nil the ivar: a defined-but-nil @test_tracker
      # behaves identically but pins `test_tracker`'s defined? check to
      # one branch for every later example in the process, which is what
      # made the dogfood branch bar order-dependent.
      SimpleCov.remove_instance_variable(:@test_tracker) if SimpleCov.instance_variable_defined?(:@test_tracker)
      SimpleCov.track_tests(false)
    end

    describe "#track_test" do
      it "just runs the block when no tracker is live" do
        expect(SimpleCov.test_tracker).to be_nil
        expect(SimpleCov.track_test("spec/a_spec.rb:1") { :ran }).to eq(:ran)
      end

      it "delegates to the live tracker" do
        tracker = instance_double(SimpleCov::TestTracker)
        allow(tracker).to receive(:track).with("spec/a_spec.rb:1").and_yield
        SimpleCov.instance_variable_set(:@test_tracker, tracker)

        expect(SimpleCov.track_test("spec/a_spec.rb:1") { :ran }).to eq(:ran)
      end
    end

    describe "#start_test_tracking" do
      before { allow(SimpleCov::TestTracker).to receive(:install_framework_hooks) }

      it "does nothing while track_tests is off" do
        SimpleCov.start_test_tracking

        expect(SimpleCov.test_tracker).to be_nil
        expect(SimpleCov::TestTracker).not_to have_received(:install_framework_hooks)
      end

      it "builds the tracker and installs the framework hooks when track_tests is on" do
        SimpleCov.track_tests

        SimpleCov.start_test_tracking

        expect(SimpleCov.test_tracker).to be_a(SimpleCov::TestTracker)
        expect(SimpleCov::TestTracker).to have_received(:install_framework_hooks)
      end

      it "keeps the tracker (and its recordings) across a restart, wiring hooks only once" do
        SimpleCov.track_tests
        SimpleCov.start_test_tracking
        tracker = SimpleCov.test_tracker

        SimpleCov.start_test_tracking

        expect(SimpleCov.test_tracker).to be(tracker)
        expect(SimpleCov::TestTracker).to have_received(:install_framework_hooks).once
      end
    end
  end
end
