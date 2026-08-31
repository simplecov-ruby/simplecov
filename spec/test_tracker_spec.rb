# frozen_string_literal: true

require "helper"
require "coverage"

RSpec.describe SimpleCov::TestTracker do
  subject(:tracker) { described_class.new(root_regex: /\A#{Regexp.escape(project_root + File::SEPARATOR)}/i) }

  let(:project_root) { File.expand_path("/proj") }
  let(:lib_file) { File.join(project_root, "lib/thing.rb") }
  let(:gem_file) { File.expand_path("/gems/rspec/lib/rspec.rb") }

  def stub_peeks(before, after)
    allow(Coverage).to receive(:peek_result).and_return(before, after)
  end

  it "refuses a granularity it does not know" do
    expect { described_class.new(granularity: :sentence) }
      .to raise_error(ArgumentError, "unknown granularity :sentence, expected one of [:test, :file]")
  end

  describe "#track" do
    it "attributes the lines whose count grew, and only those, to the test" do
      idle_file = File.join(project_root, "lib/idle.rb")
      stub_peeks(
        {lib_file => {lines: [1, 0, nil, 5]}, idle_file => {lines: [3]}},
        {lib_file => {lines: [2, 0, nil, 5]}, idle_file => {lines: [3]}}
      )

      tracker.track("spec/thing_spec.rb:1") { :ran }

      expect(tracker.recorded_map.covering(lib_file, 1)).to eq(["spec/thing_spec.rb:1"])
      expect(tracker.recorded_map.covering(lib_file, 2)).to eq([])
      expect(tracker.recorded_map.covering(lib_file, 4)).to eq([])
      expect(tracker.recorded_map.covering(idle_file, 1)).to eq([])
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
      expect(tracker.recorded_map.covering(lib_file, 1)).to eq(["spec/thing_spec.rb:1"])
    end

    it "skips files outside the project root" do
      stub_peeks(
        {gem_file => {lines: [0]}},
        {gem_file => {lines: [9]}}
      )

      tracker.track("spec/thing_spec.rb:1") { :ran }

      expect(tracker.recorded_map.covering(gem_file, 1)).to eq([])
    end

    it "attributes every executed line of a file the test itself loaded" do
      stub_peeks(
        {},
        {lib_file => {lines: [1, nil, 0]}}
      )

      tracker.track("spec/thing_spec.rb:1") { :ran }

      expect(tracker.recorded_map.covering(lib_file, 1)).to eq(["spec/thing_spec.rb:1"])
      expect(tracker.recorded_map.covering(lib_file, 3)).to eq([])
    end

    it "reads bare line arrays, the shape a foreign lines-only Coverage.start produces" do
      stub_peeks(
        {lib_file => [0, 1]},
        {lib_file => [1, 1]}
      )

      tracker.track("spec/thing_spec.rb:1") { :ran }

      expect(tracker.recorded_map.covering(lib_file, 1)).to eq(["spec/thing_spec.rb:1"])
      expect(tracker.recorded_map.covering(lib_file, 2)).to eq([])
    end

    it "has nothing to diff for a file that carries no line data at all" do
      stub_peeks(
        {lib_file => {branches: {}}},
        {lib_file => {branches: {}}, File.join(project_root, "lib/other.rb") => {methods: {}}}
      )

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

    it "attributes a same-thread nested track to both tests" do
      allow(Coverage).to receive(:peek_result).and_return(
        {lib_file => {lines: [0, 0]}},
        {lib_file => {lines: [1, 0]}},
        {lib_file => {lines: [1, 1]}},
        {lib_file => {lines: [1, 1]}}
      )

      tracker.track("spec/outer_spec.rb:1") do
        tracker.track("spec/inner_spec.rb:2") { :ran }
      end

      expect(tracker.recorded_map.covering(lib_file, 1)).to eq(["spec/outer_spec.rb:1"])
      expect(tracker.recorded_map.covering(lib_file, 2)).to eq(["spec/inner_spec.rb:2", "spec/outer_spec.rb:1"])
    end
  end

  describe "segments" do
    it "takes one peek per boundary, attributing the gap forward" do
      allow(Coverage).to receive(:peek_result).and_return(
        {lib_file => {lines: [0, 0, 0]}},
        {lib_file => {lines: [1, 0, 0]}},
        {lib_file => {lines: [1, 1, 1]}}
      )

      tracker.track("spec/first_spec.rb:1") { :ran }
      tracker.track("spec/second_spec.rb:2") { :ran }

      map = tracker.recorded_map
      expect(Coverage).to have_received(:peek_result).exactly(3).times
      expect(map.covering(lib_file, 1)).to eq(["spec/first_spec.rb:1"])
      expect(map.covering(lib_file, 2)).to eq(["spec/second_spec.rb:2"])
      expect(map.covering(lib_file, 3)).to eq(["spec/second_spec.rb:2"])
    end

    it "defers recording to the boundary, so the raw map lags until flush" do
      allow(Coverage).to receive(:peek_result).and_return(
        {lib_file => {lines: [0]}},
        {lib_file => {lines: [1]}}
      )

      tracker.track("spec/first_spec.rb:1") { :ran }

      expect(tracker.map.covering(lib_file, 1)).to eq([])
      expect(tracker.recorded_map.covering(lib_file, 1)).to eq(["spec/first_spec.rb:1"])
    end

    it "keeps one segment open across consecutive tracks of the same id, with no extra peeks" do
      allow(Coverage).to receive(:peek_result).and_return(
        {lib_file => {lines: [0, 0]}},
        {lib_file => {lines: [1, 1]}}
      )

      tracker.track("spec/first_spec.rb:1") { :ran }
      tracker.track("spec/first_spec.rb:1") { :ran }
      tracker.track("spec/first_spec.rb:1") { :ran }

      map = tracker.recorded_map
      expect(Coverage).to have_received(:peek_result).exactly(2).times
      expect(map.covering(lib_file, 1)).to eq(["spec/first_spec.rb:1"])
    end

    it "flushes from a supplied closing snapshot without peeking, for the stopped-Coverage exit path" do
      allow(Coverage).to receive(:peek_result).and_return({lib_file => {lines: [0]}})

      tracker.track("spec/first_spec.rb:1") { :ran }
      map = tracker.recorded_map(closing: {lib_file => {lines: [1]}})

      expect(Coverage).to have_received(:peek_result).once
      expect(map.covering(lib_file, 1)).to eq(["spec/first_spec.rb:1"])
    end

    it "flushes idempotently" do
      allow(Coverage).to receive(:peek_result).and_return({lib_file => {lines: [1]}})

      tracker.track("spec/first_spec.rb:1") { :ran }
      first = tracker.recorded_map.to_h

      expect(tracker.recorded_map.to_h).to eq(first)
      expect(Coverage).to have_received(:peek_result).exactly(2).times
    end
  end

  describe "file granularity", mutant_expression: ["SimpleCov::TestTracker*",
                                                   "SimpleCov::TestTracker#track"] do
    subject(:tracker) do
      described_class.new(root_regex: /\A#{Regexp.escape(project_root + File::SEPARATOR)}/i, granularity: :file)
    end

    it "attributes to the test file, merging its tests into one segment" do
      allow(Coverage).to receive(:peek_result).and_return(
        {lib_file => {lines: [0, 0, 0]}},
        {lib_file => {lines: [1, 1, 0]}},
        {lib_file => {lines: [1, 1, 1]}}
      )

      tracker.track("spec/first_spec.rb:1") { :ran }
      tracker.track("spec/first_spec.rb:9") { :ran }
      tracker.track("spec/second_spec.rb:2") { :ran }

      map = tracker.recorded_map
      expect(Coverage).to have_received(:peek_result).exactly(3).times
      expect(map.covering(lib_file, 1)).to eq(["spec/first_spec.rb"])
      expect(map.covering(lib_file, 2)).to eq(["spec/first_spec.rb"])
      expect(map.covering(lib_file, 3)).to eq(["spec/second_spec.rb"])
      expect(map.contexts).to eq(["spec/first_spec.rb", "spec/second_spec.rb"])
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

  describe "nested tracks in one thread" do
    it "stays trustworthy across sequential nested tracks" do
      allow(Coverage).to receive(:peek_result).and_return({})

      tracker.track("spec/outer_spec.rb:1") do
        tracker.track("spec/first_inner_spec.rb:2") { :ran }
        tracker.track("spec/second_inner_spec.rb:3") { :ran }
      end

      expect(tracker.poisoned?).to be(false)
      expect(tracker.recorded_map).not_to be_nil
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

      capture_stderr do
        tracker.track("spec/outer_spec.rb:1") do
          tracker.track("spec/inner_spec.rb:2") do
            Thread.new { tracker.track("spec/other_spec.rb:3") { :ran } }.value
          end
        end
      end

      expect(tracker.map.contexts).to eq([])
    end
  end

  describe "#recorded_map" do
    it "closes the open segment against a snapshot it is given" do
      allow(Coverage).to receive(:peek_result).and_return({lib_file => {lines: [0, 0]}})

      tracker.track("spec/thing_spec.rb:1") { :ran }
      map = tracker.recorded_map(closing: {lib_file => {lines: [1, 0]}})

      expect(Coverage).to have_received(:peek_result).once
      expect(map.covering(lib_file, 1)).to eq(["spec/thing_spec.rb:1"])
    end

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

    it "wraps each example in a track_test call named after its location" do
      described_class.install_rspec_hook(fake_rspec)
      example = instance_double(RSpec::Core::Example::Procsy, metadata: {location: "./spec/a_spec.rb:12"})
      allow(example).to receive(:run)
      allow(SimpleCov).to receive(:track_test).and_yield

      Object.new.instance_exec(example, &around_blocks.first)

      expect(SimpleCov).to have_received(:track_test).with("spec/a_spec.rb:12")
      expect(example).to have_received(:run)
    end

    it "installs once per process" do
      second = class_double(RSpec)
      allow(second).to receive(:configure)

      described_class.install_rspec_hook(fake_rspec)
      described_class.install_rspec_hook(second)

      expect(around_blocks.size).to eq(1)
      expect(second).not_to have_received(:configure)
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

    it "arms no watch when Minitest::Test is already there" do
      minitest = Module.new
      minitest.const_set(:Test, test_case)
      root.const_set(:Minitest, minitest)
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

    it "never forces an autoload to resolve" do
      described_class.install_minitest_hook_when_loaded(root)
      allow(SimpleCov::TestTracker::ConstantWatch).to receive(:new).and_call_original

      root.autoload(:Minitest, "some/nonexistent/minitest")

      expect(root.autoload?(:Minitest)).not_to be_nil
      expect(SimpleCov::TestTracker::ConstantWatch).not_to have_received(:new)
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

  describe SimpleCov::TestTracker::Delta do
    subject(:delta) { described_class.new(root_regex: /\A#{Regexp.escape('/app')}/) }

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
      regex = Object.new
      regex.define_singleton_method(:match?) do |path|
        asked << path
        path.start_with?("/app")
      end

      memoizing = described_class.new(root_regex: regex)
      2.times { memoizing.call({}, {"/app/a.rb" => lines([1])}) }

      expect(asked).to eq(["/app/a.rb"])
    end

    it "does not walk the lines of a file nothing touched" do
      before = {"/app/a.rb" => lines([1, 2, 3])}
      after = {"/app/a.rb" => lines([1, 2, 3])}
      walker = described_class.new(root_regex: /\A#{Regexp.escape('/app')}/)
      allow(walker).to receive(:grew?).and_call_original

      walker.call(before, after)

      expect(walker).not_to have_received(:grew?)
    end

    it "reads both shapes of per-file coverage" do
      expect(delta.call({"/app/a.rb" => [0]}, {"/app/a.rb" => [1]})).to eq("/app/a.rb" => 0b1)
      expect(delta.call({"/app/a.rb" => lines([0])}, {"/app/a.rb" => lines([1])})).to eq("/app/a.rb" => 0b1)
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
    it "ignores a constant that belongs to an ancestor" do
      ancestor = Module.new
      ancestor.const_set(:Target, Class.new)
      host = Module.new
      host.include(ancestor)

      expect(described_class.loaded_const(host, :Target)).to be_nil
    end

    it "leaves a constant that is only declared for autoload alone" do
      host = Module.new
      host.autoload(:Target, "some/nonexistent/target")

      expect(described_class.loaded_const(host, :Target)).to be_nil
    end

    it "answers a constant of its own that an ancestor merely autoloads" do
      ancestor = Module.new
      ancestor.autoload(:Target, "some/nonexistent/target")
      host = Module.new
      host.include(ancestor)
      host.const_set(:Target, :loaded)

      expect(described_class.loaded_const(host, :Target)).to eq(:loaded)
    end
  end

  describe ".minitest_test_id" do
    it "names a test by where its method is defined, relative to the root" do
      klass = Class.new do
        def name = "test_example"

        def test_example; end
      end
      stub_const("FakeLocatedTest", klass)
      _, line = klass.instance_method(:test_example).source_location

      expect(described_class.minitest_test_id(klass.new)).to eq("spec/test_tracker_spec.rb:#{line}")
    end

    it "keeps the whole path of a test defined outside the project" do
      # rubocop:disable Style/EvalWithLocation
      klass = Class.new
      klass.class_eval("def name = \"test_outside\"\n\ndef test_outside; end\n", "/outside/a_test.rb", 1)
      # rubocop:enable Style/EvalWithLocation

      expect(described_class.minitest_test_id(klass.new)).to eq("/outside/a_test.rb:3")
    end

    it "names a test method the runner kept private" do
      klass = Class.new do
        def name = "test_hidden"

      private

        def test_hidden; end
      end
      stub_const("FakePrivateTest", klass)
      _, line = klass.instance_method(:test_hidden).source_location

      expect(described_class.minitest_test_id(klass.new)).to eq("spec/test_tracker_spec.rb:#{line}")
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
      it "just runs the block when no tracker is live" do
        expect(SimpleCov.test_tracker).to be_nil
        expect(SimpleCov.track_test("spec/a_spec.rb:1") { :ran }).to eq(:ran)
      end

      it "delegates to the live tracker" do
        tracker = instance_double(SimpleCov::TestTracker)
        allow(tracker).to receive(:track).with("spec/a_spec.rb:1").and_yield
        SimpleCov.instance_variable_set(:@test_tracker, tracker)

        expect(SimpleCov.track_test("spec/a_spec.rb:1") { :ran }).to eq(:ran)
        expect(tracker).to have_received(:track).with("spec/a_spec.rb:1")
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
