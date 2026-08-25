# frozen_string_literal: true

require "helper"
require "timeout"
require "simplecov/production"

RSpec.describe SimpleCov::Production do
  # Expanded so the drive-letter prefix Windows adds ("D:/app") is part
  # of the root and the stubbed absolute paths alike.
  let(:root) { File.expand_path("/app") }
  let(:sink) { instance_double(SimpleCov::Production::FileSink, store: true) }

  after { described_class.reset! }

  # The suite itself runs under Coverage, so specs that start production
  # mode stub the runtime out from under it; the one guard spec below
  # relies on the real running Coverage instead.
  def stub_coverage(result: {})
    allow(Coverage).to receive_messages(running?: false, start: nil, suspend: nil, resume: nil,
                                        supported?: true, result: result)
  end

  def start(**options)
    described_class.start(root: root, sink: sink, flush_interval: 600, **options)
  end

  # Configure without spawning the flush thread. The examples that stub
  # `rand` drive `cycle` and `next_wait` themselves, and a live thread
  # races those stubs: it calls `rand` on its way into its first wait
  # and can outlive the example's mocks, which breaks the module's
  # method lookup mid-mutation on JRuby.
  def start_without_flush_thread(**options)
    allow(described_class).to receive(:spawn_flush_thread)
    start(**options)
  end

  def abs(relative)
    File.join(root, relative)
  end

  describe ".start" do
    it "declines when another Coverage owner is already measuring" do
      # Only running? is stubbed: a start that got past the guard would
      # blow up on the unstubbed runtime rather than measure anything.
      allow(Coverage).to receive(:running?).and_return(true)
      stderr = capture_stderr { expect(start).to be false }

      expect(stderr).to include("Coverage is already running")
      expect(described_class).not_to be_running
    end

    context "with the runtime stubbed" do
      before { stub_coverage }

      it "starts oneshot lines coverage and reports running" do
        expect(start).to be true

        expect(Coverage).to have_received(:start).with(oneshot_lines: true)
        expect(described_class).to be_running
      end

      it "declines a second start while running" do
        start
        stderr = capture_stderr { expect(start).to be false }

        expect(stderr).to include("already running")
      end

      it "declines when the runtime has no oneshot lines support" do
        allow(Coverage).to receive(:supported?).with(:oneshot_lines).and_return(false)

        stderr = capture_stderr { expect(start).to be false }
        expect(stderr).to include("oneshot")
      end

      it "rejects a non-positive flush interval" do
        expect { start(flush_interval: 0) }
          .to raise_error(SimpleCov::Production::Error, /flush_interval/)
      end

      it "rejects a sample rate outside (0, 1]" do
        expect { start(sample_rate: 0) }.to raise_error(SimpleCov::Production::Error, /sample_rate/)
        expect { start(sample_rate: 1.5) }.to raise_error(SimpleCov::Production::Error, /sample_rate/)
      end

      it "rejects a non-positive buffer ceiling" do
        expect { start(max_buffered_lines: 0) }
          .to raise_error(SimpleCov::Production::Error, /max_buffered_lines/)
      end

      # A forked worker inherits the parent's running measurement but
      # not its flush thread; `start` from the worker-boot hook picks
      # the measurement up rather than declining it as foreign.
      it "resumes the inherited measurement after a fork instead of declining" do
        start
        described_class.reset! # stands in for the fork killing the flush thread
        described_class.instance_variable_set(:@started_coverage, true)
        described_class.instance_variable_set(:@pid, Process.pid - 1)
        allow(Coverage).to receive(:running?).and_return(true)

        expect(start).to be true
        expect(Coverage).to have_received(:start).once
        expect(described_class).to be_running
      end

      it "rejects a fractional sample rate when the runtime cannot suspend" do
        allow(Coverage).to receive(:respond_to?).and_call_original
        allow(Coverage).to receive(:respond_to?).with(:suspend).and_return(false)

        expect { start(sample_rate: 0.5) }
          .to raise_error(SimpleCov::Production::Error, /suspend/)
      end
    end
  end

  describe ".flush" do
    before do
      stub_coverage(result: {
                      abs("lib/a.rb") => {oneshot_lines: [3, 1]},
                      abs("lib/quiet.rb") => {oneshot_lines: []},
                      File.expand_path("/elsewhere/b.rb") => {oneshot_lines: [7]}
                    })
      start
    end

    it "delivers root-relative sorted lines to the sink, dropping out-of-root files" do
      expect(described_class.flush).to be true

      expect(sink).to have_received(:store).with("lib/a.rb" => [1, 3])
      expect(Coverage).to have_received(:result).with(stop: false, clear: true)
    end

    it "delivers only the delta after a successful flush" do
      described_class.flush
      allow(Coverage).to receive(:result).and_return(abs("lib/a.rb") => {oneshot_lines: [5]})

      described_class.flush

      expect(sink).to have_received(:store).with("lib/a.rb" => [5])
    end

    it "keeps the pending lines for the next flush when the sink fails" do
      allow(sink).to receive(:store).and_raise(Errno::ECONNREFUSED)
      stderr = capture_stderr { expect(described_class.flush).to be false }
      expect(stderr).to include("flush failed")

      allow(sink).to receive(:store).and_return(true)
      allow(Coverage).to receive(:result).and_return(abs("lib/a.rb") => {oneshot_lines: [5]})
      described_class.flush

      expect(sink).to have_received(:store).with("lib/a.rb" => [1, 3, 5]).once
    end

    it "reports an empty flush as a success without touching the sink" do
      allow(Coverage).to receive(:result).and_return({})
      expect(described_class.flush).to be true
      expect(sink).not_to have_received(:store)
    end
  end

  describe "the buffer ceiling" do
    before do
      stub_coverage(result: {abs("lib/a.rb") => {oneshot_lines: [1, 2, 3]}})
      start(max_buffered_lines: 2)
      allow(sink).to receive(:store).and_raise(Errno::ECONNREFUSED)
    end

    it "drops the pending buffer when a failed flush leaves it over the ceiling" do
      stderr = capture_stderr { described_class.flush }
      expect(stderr).to include("buffer ceiling")

      allow(sink).to receive(:store).and_return(true)
      allow(Coverage).to receive(:result).and_return(abs("lib/b.rb") => {oneshot_lines: [9]})
      described_class.flush

      expect(sink).to have_received(:store).with("lib/b.rb" => [9]).once
    end

    it "keeps a pending buffer at or under the ceiling and folds it into the next flush" do
      allow(Coverage).to receive(:result).and_return(abs("lib/a.rb") => {oneshot_lines: [1, 2]})
      capture_stderr { described_class.flush }

      allow(sink).to receive(:store).and_return(true)
      allow(Coverage).to receive(:result).and_return(abs("lib/b.rb") => {oneshot_lines: [9]})
      described_class.flush

      expect(sink).to have_received(:store).with("lib/a.rb" => [1, 2], "lib/b.rb" => [9])
    end
  end

  describe "sampling" do
    before do
      stub_coverage
      start_without_flush_thread(sample_rate: 0.5)
    end

    it "suspends measurement for an unsampled cycle and resumes for a sampled one" do
      allow(described_class).to receive(:rand).and_return(0.9)
      described_class.send(:cycle)
      expect(Coverage).to have_received(:suspend).once

      allow(described_class).to receive(:rand).and_return(0.1)
      described_class.send(:cycle)
      expect(Coverage).to have_received(:resume).once
    end

    it "leaves the measurement state alone when consecutive cycles agree" do
      allow(described_class).to receive(:rand).and_return(0.9, 0.9)
      described_class.send(:cycle)
      described_class.send(:cycle)

      expect(Coverage).to have_received(:suspend).once
    end
  end

  describe ".flush before start" do
    it "answers false rather than touching anything" do
      expect(described_class.flush).to be false
    end
  end

  describe "the default sink" do
    it "is a FileSink under the root's tmp directory" do
      stub_coverage
      described_class.start(root: root, flush_interval: 600)

      configured = described_class.instance_variable_get(:@sink)
      expect(configured).to be_a(SimpleCov::Production::FileSink)
      expect(configured.path).to eq(File.join(root, "tmp", "simplecov", "production.json"))
    end
  end

  describe ".stop" do
    before do
      stub_coverage(result: {abs("lib/a.rb") => {oneshot_lines: [4]}})
      start
    end

    it "flushes the final delta, stops Coverage, and stops running" do
      expect(described_class.stop).to be true

      expect(sink).to have_received(:store).with("lib/a.rb" => [4])
      expect(Coverage).to have_received(:result).with(stop: true, clear: true)
      expect(described_class).not_to be_running
    end

    it "returns false when nothing is running" do
      described_class.stop
      expect(described_class.stop).to be false
    end

    # The defensive arm: a flush thread that died on its own (or a
    # state carried over a fork) must not keep `stop` from finishing.
    it "still stops when the flush thread is already gone" do
      described_class.instance_variable_get(:@thread)&.kill&.join
      described_class.instance_variable_set(:@thread, nil)

      expect(described_class.stop).to be true
      expect(described_class).not_to be_running
    end
  end

  describe "the flush thread" do
    let(:queue_sink) do
      Class.new do
        def initialize
          @stores = Queue.new
        end

        attr_reader :stores

        def store(coverage)
          @stores << coverage
        end
      end.new
    end

    it "flushes on the configured interval without being asked" do
      stub_coverage(result: {abs("lib/a.rb") => {oneshot_lines: [2]}})
      described_class.start(root: root, sink: queue_sink, flush_interval: 0.05)

      stored = Timeout.timeout(5) { queue_sink.stores.pop }
      expect(stored).to eq("lib/a.rb" => [2])
    end
  end

  describe ".at_exit_stop" do
    before { stub_coverage }

    it "stops when running and does nothing otherwise" do
      start
      described_class.send(:at_exit_stop)
      expect(described_class).not_to be_running

      described_class.send(:at_exit_stop)
    end
  end
end
