# frozen_string_literal: true

require "helper"
require "timeout"
require "simplecov/production"

RSpec.describe SimpleCov::Production do
  let(:root) { File.expand_path("/app") }
  let(:sink) { instance_double(SimpleCov::Production::FileSink, store: true) }

  after { described_class.reset! }

  def stub_coverage(result: {})
    allow(Coverage).to receive_messages(running?: false, start: nil, suspend: nil, resume: nil,
      supported?: true, result: result)
  end

  def start(**)
    described_class.start(root: root, sink: sink, flush_interval: 600, **)
  end

  def start_without_flush_thread(**)
    allow(described_class).to receive(:spawn_flush_thread)
    start(**)
  end

  def abs(relative)
    File.join(root, relative)
  end

  def mutex
    described_class.instance_variable_get(:@mutex)
  end

  def sleeping_flush_thread
    thread = described_class.instance_variable_get(:@thread)
    Timeout.timeout(5) { Thread.pass until thread.status == "sleep" }
    thread
  end

  def expect_declined_start(message)
    stderr = capture_stderr { expect(start).to be false }
    expect(stderr).to include(message)
  end

  describe ".start" do
    it "declines when another Coverage owner is already measuring" do
      allow(Coverage).to receive(:running?).and_return(true)

      expect_declined_start("Coverage is already running")
    end

    it "does not report running when another Coverage owner is already measuring" do
      allow(Coverage).to receive(:running?).and_return(true)
      without_stderr { start }

      expect(described_class).not_to be_running
    end

    context "with the runtime stubbed" do
      before { stub_coverage }

      def simulate_fork
        start
        described_class.reset!
        described_class.instance_variable_set(:@started_coverage, true)
        described_class.instance_variable_set(:@pid, Process.pid - 1)
        allow(Coverage).to receive(:running?).and_return(true)
      end

      it "answers true when it starts" do
        expect(start).to be true
      end

      it "starts oneshot lines coverage" do
        start

        expect(Coverage).to have_received(:start).with(oneshot_lines: true)
      end

      it "reports running once it has started" do
        start

        expect(described_class).to be_running
      end

      it "installs the at_exit hook" do
        start

        expect(described_class.instance_variable_get(:@at_exit_installed)).to be(true)
      end

      it "spawns the flush thread" do
        start

        expect(described_class.instance_variable_get(:@thread)).to be_a(Thread)
      end

      it "measures at the full rate on a runtime that cannot suspend" do
        allow(Coverage).to receive(:respond_to?).and_call_original
        allow(Coverage).to receive(:respond_to?).with(:suspend).and_return(false)

        expect(start).to be true
      end

      it "assumes oneshot lines on a runtime that cannot be asked" do
        allow(Coverage).to receive(:respond_to?).and_call_original
        allow(Coverage).to receive(:respond_to?).with(:supported?).and_return(false)
        allow(Coverage).to receive(:supported?).and_raise(NoMethodError)

        expect(start).to be true
      end

      it "declines a second start while running" do
        start

        expect_declined_start("already running")
      end

      it "declines when the runtime has no oneshot lines support" do
        allow(Coverage).to receive(:supported?).with(:oneshot_lines).and_return(false)

        expect_declined_start("oneshot")
      end

      it "rejects a non-positive flush interval" do
        expect { start(flush_interval: 0) }
          .to raise_error(SimpleCov::Production::Error, /flush_interval/)
      end

      it "rejects a sample rate of zero" do
        expect { start(sample_rate: 0) }.to raise_error(SimpleCov::Production::Error, /sample_rate/)
      end

      it "rejects a sample rate above one" do
        expect { start(sample_rate: 1.5) }.to raise_error(SimpleCov::Production::Error, /sample_rate/)
      end

      it "rejects a non-positive buffer ceiling" do
        expect { start(max_buffered_lines: 0) }
          .to raise_error(SimpleCov::Production::Error, /max_buffered_lines/)
      end

      it "rejects a negative flush jitter" do
        expect { start(flush_jitter: -1) }.to raise_error(SimpleCov::Production::Error, /flush_jitter/)
      end

      it "rejects a non-numeric flush jitter" do
        expect { start(flush_jitter: "6") }.to raise_error(SimpleCov::Production::Error, /flush_jitter/)
      end

      it "resumes the inherited measurement after a fork instead of declining" do
        simulate_fork

        expect(start).to be true
      end

      it "does not start Coverage a second time after a fork" do
        simulate_fork
        start

        expect(Coverage).to have_received(:start).once
      end

      it "reports running once it has resumed an inherited measurement" do
        simulate_fork
        start

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
        File.expand_path("/elsewhere/b.rb") => {oneshot_lines: [7]},
        abs("lib/quiet.rb") => {oneshot_lines: []},
        abs("lib/a.rb") => {oneshot_lines: [3, 1]}
      })
      start
    end

    def flush_failing_then_succeeding(second_result)
      allow(sink).to receive(:store).and_raise(Errno::ECONNREFUSED)
      without_stderr { described_class.flush }
      allow(sink).to receive(:store).and_return(true)
      allow(Coverage).to receive(:result).and_return(second_result)
      described_class.flush
    end

    it "reports a delivered flush as a success" do
      expect(described_class.flush).to be true
    end

    it "delivers root-relative sorted lines to the sink, dropping out-of-root files" do
      described_class.flush

      expect(sink).to have_received(:store).with("lib/a.rb" => [1, 3])
    end

    it "takes the result without stopping Coverage, and clears it" do
      described_class.flush

      expect(Coverage).to have_received(:result).with(stop: false, clear: true)
    end

    it "delivers only the delta after a successful flush" do
      described_class.flush
      allow(Coverage).to receive(:result).and_return(abs("lib/a.rb") => {oneshot_lines: [5]})

      described_class.flush

      expect(sink).to have_received(:store).with("lib/a.rb" => [5])
    end

    it "names the failure the sink raised, class and message" do
      error = Errno::ECONNREFUSED.new("the sink")
      allow(sink).to receive(:store).and_raise(error)

      expect(capture_stderr { described_class.flush })
        .to eq("[SimpleCov::Production] flush failed (Errno::ECONNREFUSED: #{error.message}); retrying next interval\n")
    end

    it "reports a failed flush as a failure" do
      allow(sink).to receive(:store).and_raise(Errno::ECONNREFUSED)

      expect(without_stderr { described_class.flush }).to be false
    end

    it "says on stderr that the flush failed" do
      allow(sink).to receive(:store).and_raise(Errno::ECONNREFUSED)

      expect(capture_stderr { described_class.flush }).to include("flush failed")
    end

    it "keeps the pending lines for the next flush when the sink fails" do
      flush_failing_then_succeeding(abs("lib/a.rb") => {oneshot_lines: [5]})

      expect(sink).to have_received(:store).with("lib/a.rb" => [1, 3, 5]).once
    end

    it "drains and delivers under the lock" do
      held = []
      allow(described_class).to receive(:pull_pending) { held << mutex.owned? }
      allow(described_class).to receive(:push_pending) { held << mutex.owned? }

      described_class.flush

      expect(held).to eq([true, true])
    end

    it "reports an empty flush as a success" do
      allow(Coverage).to receive(:result).and_return({})

      expect(described_class.flush).to be true
    end

    it "leaves the sink alone on an empty flush" do
      allow(Coverage).to receive(:result).and_return({})
      described_class.flush

      expect(sink).not_to have_received(:store)
    end
  end

  describe "what a drain skips" do
    let(:mixed_result) do
      {abs("lib/silent.rb") => {},
       abs("lib/empty.rb") => {oneshot_lines: []},
       abs("lib/a.rb") => {oneshot_lines: [1]}}
    end

    before { stub_coverage }

    it "skips a file with no oneshot lines and keeps draining the rest" do
      start
      allow(Coverage).to receive(:result).and_return(mixed_result)

      described_class.flush

      expect(sink).to have_received(:store).with("lib/a.rb" => [1])
    end
  end

  describe "the buffer ceiling" do
    before do
      stub_coverage(result: {abs("lib/a.rb") => {oneshot_lines: [1, 2, 3]}})
      start(max_buffered_lines: 2)
      allow(sink).to receive(:store).and_raise(Errno::ECONNREFUSED)
    end

    def flush_then_flush(second_result)
      without_stderr { described_class.flush }
      allow(sink).to receive(:store).and_return(true)
      allow(Coverage).to receive(:result).and_return(second_result)
      described_class.flush
    end

    it "says on stderr that it dropped the buffer" do
      expect(capture_stderr { described_class.flush }).to include("buffer ceiling")
    end

    it "drops the pending buffer when a failed flush leaves it over the ceiling" do
      flush_then_flush(abs("lib/b.rb") => {oneshot_lines: [9]})

      expect(sink).to have_received(:store).with("lib/b.rb" => [9]).once
    end

    it "keeps a pending buffer at or under the ceiling and folds it into the next flush" do
      allow(Coverage).to receive(:result).and_return(abs("lib/a.rb") => {oneshot_lines: [1, 2]})
      flush_then_flush(abs("lib/b.rb") => {oneshot_lines: [9]})

      expect(sink).to have_received(:store).with("lib/a.rb" => [1, 2], "lib/b.rb" => [9])
    end
  end

  describe "sampling" do
    before do
      stub_coverage
      start_without_flush_thread(sample_rate: 0.5)
    end

    it "suspends measurement for an unsampled cycle" do
      allow(described_class).to receive(:rand).and_return(0.9)

      described_class.send(:cycle)

      expect(Coverage).to have_received(:suspend).once
    end

    it "resumes measurement for a sampled cycle that follows an unsampled one" do
      allow(described_class).to receive(:rand).and_return(0.9)
      described_class.send(:cycle)
      allow(described_class).to receive(:rand).and_return(0.1)

      described_class.send(:cycle)

      expect(Coverage).to have_received(:resume).once
    end

    it "leaves a suspended cycle suspended rather than resuming it" do
      allow(described_class).to receive(:rand).and_return(0.9)
      described_class.send(:cycle)

      described_class.send(:cycle)

      expect(Coverage).not_to have_received(:resume)
    end

    it "leaves a measured cycle measuring rather than suspending it" do
      allow(described_class).to receive(:rand).and_return(0.1)

      described_class.send(:cycle)

      expect(Coverage).not_to have_received(:suspend)
    end

    it "leaves the measurement state alone when consecutive cycles agree" do
      allow(described_class).to receive(:rand).and_return(0.9, 0.9)
      described_class.send(:cycle)
      described_class.send(:cycle)

      expect(Coverage).to have_received(:suspend).once
    end
  end

  describe "what counts as running" do
    it "answers false, not nil, before anything has started" do
      described_class.instance_variable_set(:@running, nil)

      expect(described_class.running?).to be(false)
    end

    it "answers false for a measurement another process started" do
      stub_coverage
      start
      described_class.instance_variable_set(:@pid, Process.pid - 1)

      expect(described_class.running?).to be(false)
    end
  end

  describe ".flush before start" do
    it "answers false rather than touching anything" do
      expect(described_class.flush).to be false
    end
  end

  describe "the default sink", mutant_expression: ["SimpleCov::Production*",
    "SimpleCov::Production.start"] do
    it "is a FileSink" do
      stub_coverage
      described_class.start(root: root, flush_interval: 600)

      expect(described_class.instance_variable_get(:@sink)).to be_a(SimpleCov::Production::FileSink)
    end

    it "sits under the root's tmp directory" do
      stub_coverage
      described_class.start(root: root, flush_interval: 600)

      expect(described_class.instance_variable_get(:@sink).path)
        .to eq(File.join(root, "tmp", "simplecov", "production.json"))
    end
  end

  describe ".stop" do
    before do
      stub_coverage(result: {abs("lib/a.rb") => {oneshot_lines: [4]}})
      start
    end

    it "reports a stop it carried out" do
      expect(described_class.stop).to be true
    end

    it "flushes the final delta" do
      described_class.stop

      expect(sink).to have_received(:store).with("lib/a.rb" => [4])
    end

    it "stops Coverage and clears it" do
      described_class.stop

      expect(Coverage).to have_received(:result).with(stop: true, clear: true)
    end

    it "stops running" do
      described_class.stop

      expect(described_class).not_to be_running
    end

    it "returns false when nothing is running" do
      described_class.stop
      expect(described_class.stop).to be false
    end

    it "wakes the flush thread rather than waiting out the interval" do
      thread = sleeping_flush_thread

      Timeout.timeout(10) { described_class.stop }

      expect(thread).not_to be_alive
    end

    it "waits for the flush thread to wind down before returning" do
      thread = described_class.instance_variable_get(:@thread)
      allow(thread).to receive(:join).and_call_original

      described_class.stop

      expect(thread).to have_received(:join)
    end

    it "delivers the final delta under the lock" do
      held = []
      allow(described_class).to receive(:pull_pending) { held << mutex.owned? }
      allow(described_class).to receive(:push_pending) { held << mutex.owned? }

      described_class.stop

      expect(held).to eq([true, true])
    end

    it "still stops when the flush thread is already gone" do
      forget_flush_thread

      expect(described_class.stop).to be true
    end

    it "stops running even when the flush thread is already gone" do
      forget_flush_thread
      described_class.stop

      expect(described_class).not_to be_running
    end

    def forget_flush_thread
      described_class.instance_variable_get(:@thread)&.kill&.join
      described_class.instance_variable_set(:@thread, nil)
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

    it "runs under a name a process listing can explain" do
      stub_coverage
      start

      expect(described_class.instance_variable_get(:@thread))
        .to be_a(Thread).and have_attributes(name: "SimpleCov::Production flusher")
    end

    it "is woken by stop rather than waiting out the interval" do
      stub_coverage
      described_class.start(root: root, sink: queue_sink, flush_interval: 600)
      thread = sleeping_flush_thread

      Timeout.timeout(10) { described_class.stop }

      expect(thread).not_to be_alive
    end

    it "does not drain once more on its way out" do
      stub_coverage(result: {abs("lib/a.rb") => {oneshot_lines: [1]}})
      described_class.start(root: root, sink: queue_sink, flush_interval: 600)
      sleeping_flush_thread

      Timeout.timeout(10) { described_class.stop }

      expect(queue_sink.stores.size).to eq(1)
    end

    it "flushes on the configured interval without being asked" do
      stub_coverage(result: {abs("lib/a.rb") => {oneshot_lines: [2]}})
      described_class.start(root: root, sink: queue_sink, flush_interval: 0.05)

      stored = Timeout.timeout(5) { queue_sink.stores.pop }
      expect(stored).to eq("lib/a.rb" => [2])
    end
  end

  describe "waking the flush thread" do
    before do
      stub_coverage
      start
    end

    it "signals under the lock" do
      expect(lock_held_while_signalling).to be(true)
    end

    def lock_held_while_signalling
      held = nil
      waiter = described_class.instance_variable_get(:@waiter)
      allow(waiter).to receive(:signal).and_wrap_original do |original|
        held = mutex.owned?
        original.call
      end
      described_class.send(:wake_flush_thread)
      held
    end
  end

  describe "flush jitter" do
    before { stub_coverage }

    it "waits the interval plus a fresh random share of the jitter" do
      start_without_flush_thread(flush_jitter: 60)
      allow(described_class).to receive(:rand).and_return(0.5)

      expect(described_class.send(:interval_with_jitter)).to eq(630)
    end

    it "defaults the jitter to a tenth of the flush interval" do
      start_without_flush_thread
      allow(described_class).to receive(:rand).and_return(1.0)

      expect(described_class.send(:interval_with_jitter)).to eq(660)
    end

    it "waits exactly the interval when the jitter is zero" do
      start(flush_jitter: 0)

      expect(described_class.send(:interval_with_jitter)).to eq(600)
    end
  end

  describe "what start configures",
    mutant_expression: ["SimpleCov::Production*", "SimpleCov::Production.start"] do
    before { stub_coverage }

    def configured(name)
      described_class.instance_variable_get(:"@#{name}")
    end

    context "with every keyword given" do
      before do
        described_class.start(root: root, sink: sink, flush_interval: 30, flush_jitter: 7,
          sample_rate: 0.25, max_buffered_lines: 42)
      end

      it "carries the sink through" do
        expect(configured(:sink)).to be(sink)
      end

      it "carries the flush interval through" do
        expect(configured(:flush_interval)).to eq(30)
      end

      it "carries the flush jitter through" do
        expect(configured(:flush_jitter)).to eq(7)
      end

      it "carries the sample rate through" do
        expect(configured(:sample_rate)).to eq(0.25)
      end

      it "carries the buffer ceiling through" do
        expect(configured(:max_buffered_lines)).to eq(42)
      end

      it "carries the root through as a prefix" do
        expect(configured(:root_prefix)).to eq(File.expand_path(root) + File::SEPARATOR)
      end
    end

    context "without the optional keywords" do
      before { described_class.start(root: root, sink: sink) }

      it "defaults the flush interval to a minute" do
        expect(configured(:flush_interval)).to eq(60)
      end

      it "defaults the flush jitter to a tenth of that minute" do
        expect(configured(:flush_jitter)).to eq(6.0)
      end

      it "defaults the sample rate to the full rate" do
        expect(configured(:sample_rate)).to eq(1.0)
      end

      it "defaults the buffer ceiling to a million lines" do
        expect(configured(:max_buffered_lines)).to eq(1_000_000)
      end
    end

    context "when a parent process left a pending buffer behind" do
      before do
        described_class.instance_variable_set(:@pending, {"lib/parent.rb" => Set[1]})
        start
      end

      it "measures from the first interval" do
        expect(configured(:measuring)).to be true
      end

      it "takes the process it started in" do
        expect(configured(:pid)).to eq(Process.pid)
      end

      it "clears the buffer it inherited" do
        expect(configured(:pending)).to eq({})
      end
    end

    it "resolves a relative root once, up front" do
      described_class.start(root: "app", sink: sink)

      expect(configured(:root_prefix)).to eq(File.expand_path("app") + File::SEPARATOR)
    end

    it "defaults the root to the working directory" do
      allow(Dir).to receive(:pwd).and_return(root)
      described_class.start(sink: sink, flush_interval: 600)

      expect(configured(:root_prefix)).to eq(File.expand_path(root) + File::SEPARATOR)
    end
  end

  describe ".reset!" do
    before { stub_coverage }

    context "when a started run with a pending buffer is reset" do
      before do
        start
        described_class.instance_variable_set(:@pending, {"lib/a.rb" => Set[1]})
        described_class.reset!
      end

      it "no longer reports running" do
        expect(described_class).not_to be_running
      end

      it "clears the running flag to false rather than nil" do
        expect(described_class.instance_variable_get(:@running)).to be false
      end

      it "clears the process it recorded" do
        expect(described_class.instance_variable_get(:@pid)).to be_nil
      end

      it "clears the pending buffer" do
        expect(described_class.instance_variable_get(:@pending)).to eq({})
      end

      it "clears the flush thread" do
        expect(described_class.instance_variable_get(:@thread)).to be_nil
      end

      it "clears the record that it started Coverage" do
        expect(described_class.instance_variable_get(:@started_coverage)).to be false
      end

      it "leaves the at_exit registration in place" do
        expect(described_class.instance_variable_get(:@at_exit_installed)).to be true
      end
    end

    it "wakes the flush thread rather than waiting out the interval" do
      start
      thread = sleeping_flush_thread

      Timeout.timeout(10) { described_class.reset! }

      expect(thread).not_to be_alive
    end

    it "waits for the flush thread to wind down before clearing it" do
      start
      thread = sleeping_flush_thread
      allow(thread).to receive(:join).and_call_original

      described_class.reset!

      expect(thread).to have_received(:join)
    end

    it "does nothing about a thread that was never spawned" do
      described_class.instance_variable_set(:@mutex, nil)

      expect { described_class.reset! }.not_to raise_error
    end
  end

  describe "the sampling duty cycle" do
    before { stub_coverage }

    it "never suspends at the full rate" do
      start_without_flush_thread(sample_rate: 1.0)
      allow(described_class).to receive(:rand).and_return(0.99)

      described_class.send(:cycle)

      expect(Coverage).not_to have_received(:suspend)
    end

    it "never resumes at the full rate" do
      start_without_flush_thread(sample_rate: 1.0)
      allow(described_class).to receive(:rand).and_return(0.99)

      described_class.send(:cycle)

      expect(Coverage).not_to have_received(:resume)
    end

    it "does not even draw a sample at the full rate" do
      start_without_flush_thread(sample_rate: 1.0)
      allow(described_class).to receive(:rand).and_call_original

      described_class.send(:cycle)

      expect(described_class).not_to have_received(:rand)
    end

    it "records an unsampled cycle as not measuring" do
      start_without_flush_thread(sample_rate: 0.5)
      allow(described_class).to receive(:rand).and_return(0.9)

      described_class.send(:cycle)

      expect(described_class.instance_variable_get(:@measuring)).to be false
    end

    it "records a sampled cycle that follows an unsampled one as measuring" do
      start_without_flush_thread(sample_rate: 0.5)
      allow(described_class).to receive(:rand).and_return(0.9, 0.1)
      described_class.send(:cycle)

      described_class.send(:cycle)

      expect(described_class.instance_variable_get(:@measuring)).to be true
    end

    it "resumes only after a suspension, not on every sampled cycle" do
      start_without_flush_thread(sample_rate: 0.5)
      allow(described_class).to receive(:rand).and_return(0.1, 0.1)

      described_class.send(:cycle)
      described_class.send(:cycle)

      expect(Coverage).not_to have_received(:resume)
    end
  end

  describe "starting in a forked child", mutant_expression: ["SimpleCov::Production*",
    "SimpleCov::Production.start"] do
    def inherit_measurement
      stub_coverage
      start
      described_class.instance_variable_set(:@pid, Process.pid - 1)
      described_class.instance_variable_set(:@running, false)
      allow(Coverage).to receive(:running?).and_return(true)
    end

    it "picks the inherited measurement back up" do
      inherit_measurement

      expect(start).to be true
    end

    it "does not start Coverage again in the child" do
      inherit_measurement
      start

      expect(Coverage).to have_received(:start).once
    end

    it "still declines a running Coverage it did not start itself" do
      stub_coverage
      described_class.instance_variable_set(:@started_coverage, false)
      allow(Coverage).to receive(:running?).and_return(true)

      expect_declined_start("Coverage is already running")
    end

    it "declines a measurement it started in this very process" do
      stub_coverage
      described_class.instance_variable_set(:@started_coverage, true)
      described_class.instance_variable_set(:@pid, Process.pid)
      allow(Coverage).to receive(:running?).and_return(true)

      expect_declined_start("Coverage is already running")
    end

    it "declines a measurement with no process recorded against it" do
      stub_coverage
      described_class.instance_variable_set(:@started_coverage, true)
      described_class.instance_variable_set(:@pid, nil)
      allow(Coverage).to receive(:running?).and_return(true)

      expect_declined_start("Coverage is already running")
    end

    it "declines another tool's measurement even from a different process" do
      stub_coverage
      described_class.instance_variable_set(:@started_coverage, false)
      described_class.instance_variable_set(:@pid, Process.pid - 1)
      allow(Coverage).to receive(:running?).and_return(true)

      expect_declined_start("Coverage is already running")
    end
  end

  describe "the at_exit registration" do
    before do
      stub_coverage
      described_class.instance_variable_set(:@at_exit_installed, nil)
    end

    after { described_class.instance_variable_set(:@at_exit_installed, true) }

    it "registers exactly one hook, however many times start is called" do
      allow(described_class).to receive(:at_exit)

      described_class.send(:install_at_exit)
      described_class.send(:install_at_exit)

      expect(described_class).to have_received(:at_exit).once
    end

    it "records that the hook is installed" do
      allow(described_class).to receive(:at_exit)

      described_class.send(:install_at_exit)

      expect(described_class.instance_variable_get(:@at_exit_installed)).to be true
    end

    it "stops production coverage when the hook fires" do
      hook = captured_at_exit_hook
      allow(described_class).to receive(:stop)

      hook.call

      expect(described_class).to have_received(:stop)
    end

    def captured_at_exit_hook
      hook = nil
      allow(described_class).to receive(:at_exit) { |&block| hook = block }
      described_class.send(:install_at_exit)
      hook
    end
  end
end
