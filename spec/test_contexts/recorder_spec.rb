# frozen_string_literal: true

require "helper"
require "simplecov/test_contexts/recorder"

RSpec.describe SimpleCov::TestContexts::Recorder do
  let(:root_regex) { %r{\A/proj/} }

  def recorder_with(*snapshots)
    queue = snapshots
    described_class.new(snapshot: -> { queue.shift }, root_regex: root_regex)
  end

  it "attributes hit-count increases to the wrapped test" do
    recorder = recorder_with(
      {"/proj/a.rb" => {lines: [1, 0, nil]}},
      {"/proj/a.rb" => {lines: [1, 2, nil]}}
    )
    recorder.record("t1", "test one") { :done }

    expect(recorder.to_map.to_h).to eq(
      "version" => 1,
      "tests" => [["t1", "test one"]],
      "files" => {"/proj/a.rb" => {"0" => "2"}}
    )
  end

  it "returns the block's value" do
    recorder = recorder_with({}, {})

    expect(recorder.record("t1") { :value }).to eq :value
  end

  it "records a test that covered nothing in the tests table only" do
    lines = {"/proj/a.rb" => {lines: [1]}}
    recorder = recorder_with(lines, lines)
    recorder.record("t1") { :done }

    expect(recorder.to_map.to_h).to include("tests" => [%w[t1 t1]], "files" => {})
  end

  it "attributes every executed line of a file loaded during the test" do
    recorder = recorder_with({}, {"/proj/new.rb" => {lines: [1, nil, 0, 2]}})
    recorder.record("t1") { :done }

    # lines 1 and 4 => 0b1001
    expect(recorder.to_map.to_h["files"]).to eq("/proj/new.rb" => {"0" => "9"})
  end

  it "ignores paths outside the project root" do
    recorder = recorder_with(
      {"/gems/other.rb" => {lines: [0]}},
      {"/gems/other.rb" => {lines: [5]}}
    )
    recorder.record("t1") { :done }

    expect(recorder.to_map.to_h["files"]).to eq({})
  end

  it "reads bare line arrays as JRuby's Coverage reports them" do
    recorder = recorder_with(
      {"/proj/a.rb" => [0, nil]},
      {"/proj/a.rb" => [1, nil]}
    )
    recorder.record("t1") { :done }

    expect(recorder.to_map.to_h["files"]).to eq("/proj/a.rb" => {"0" => "1"})
  end

  it "skips entries without line data" do
    recorder = recorder_with(
      {"/proj/a.rb" => {branches: {}}},
      {"/proj/a.rb" => {branches: {}}}
    )
    recorder.record("t1") { :done }

    expect(recorder.to_map.to_h["files"]).to eq({})
  end

  it "still attributes the delta when the test raises" do
    recorder = recorder_with(
      {"/proj/a.rb" => {lines: [0]}},
      {"/proj/a.rb" => {lines: [1]}}
    )

    expect { recorder.record("t1") { raise "boom" } }.to raise_error("boom")
    expect(recorder.to_map.to_h["files"]).to eq("/proj/a.rb" => {"0" => "1"})
  end

  it "attributes lines executed between tests to no test" do
    recorder = recorder_with(
      {"/proj/a.rb" => {lines: [0, 0]}},
      {"/proj/a.rb" => {lines: [1, 0]}},
      # a before hook ran line 2 between the tests
      {"/proj/a.rb" => {lines: [1, 1]}},
      {"/proj/a.rb" => {lines: [2, 1]}}
    )
    recorder.record("t1") { :done }
    recorder.record("t2") { :done }

    expect(recorder.to_map.to_h["files"]).to eq("/proj/a.rb" => {"0" => "1", "1" => "1"})
  end

  it "merges repeated recordings of the same test id" do
    recorder = recorder_with(
      {"/proj/a.rb" => {lines: [0, 0]}},
      {"/proj/a.rb" => {lines: [1, 0]}},
      {"/proj/a.rb" => {lines: [1, 0]}},
      {"/proj/a.rb" => {lines: [1, 1]}}
    )
    recorder.record("t1") { :done }
    recorder.record("t1") { :done }

    expect(recorder.to_map.to_h).to include(
      "tests" => [%w[t1 t1]],
      "files" => {"/proj/a.rb" => {"0" => "3"}}
    )
  end

  it "rebalances the depth counter when a snapshot raises, instead of poisoning later tests" do
    calls = 0
    flaky = lambda do
      calls += 1
      # The first test's after-snapshot: something stopped Coverage mid-suite.
      raise "peek failed" if calls == 2

      {"/proj/a.rb" => {lines: [calls]}}
    end
    recorder = described_class.new(snapshot: flaky, root_regex: root_regex)

    expect { recorder.record("t1") { :done } }.to raise_error("peek failed")

    stderr = capture_stderr { recorder.record("t2") { :done } }
    expect(stderr).to be_empty
    expect(recorder).not_to be_poisoned
    expect(recorder.to_map.to_h["tests"]).to eq [%w[t1 t1], %w[t2 t2]]
  end

  describe "overlapping records" do
    it "poisons the recorder and warns once" do
      recorder = recorder_with({}, {}, {})

      stderr = capture_stderr do
        recorder.record("outer") do
          recorder.record("inner") { :done }
          recorder.record("second-inner") { :done }
        end
      end

      expect(recorder).to be_poisoned
      expect(recorder.to_map).to be_nil
      expect(stderr.scan("parallel threads").size).to eq 1
    end

    it "stops taking snapshots once poisoned" do
      calls = 0
      counting_snapshot = lambda do
        calls += 1
        {}
      end
      recorder = described_class.new(snapshot: counting_snapshot, root_regex: root_regex)

      capture_stderr do
        recorder.record("outer") { recorder.record("inner") { :done } }
      end
      recorder.record("later") { :done }

      # only the outer record's before-snapshot was taken
      expect(calls).to eq 1
    end

    it "respects print_errors when warning" do
      allow(SimpleCov).to receive(:print_errors).and_return(false)
      recorder = recorder_with({}, {})

      stderr = capture_stderr do
        recorder.record("outer") { recorder.record("inner") { :done } }
      end

      expect(stderr).to be_empty
      expect(recorder).to be_poisoned
    end
  end

  it "records through the real Coverage.peek_result by default" do
    require "coverage"
    # The dogfood bootstrap keeps a session running; outside it (say,
    # SIMPLECOV_NO_DOGFOOD=1) peek_result needs one started here.
    Coverage.start(lines: true) unless Coverage.running?
    recorder = described_class.new
    recorder.record("live") { :done }

    map = recorder.to_map
    expect(map).to be_a(SimpleCov::TestContexts::Map)
    expect(map.tests).to eq [%w[live live]]
  end
end
