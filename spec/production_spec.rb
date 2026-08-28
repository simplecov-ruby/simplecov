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

  def mutex
    described_class.instance_variable_get(:@mutex)
  end

  # The flush thread spends its life asleep on the condition variable,
  # so anything asserting how it is woken has to let it get there first.
  def sleeping_flush_thread
    thread = described_class.instance_variable_get(:@thread)
    Timeout.timeout(5) { Thread.pass until thread.status == "sleep" }
    thread
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

      it "installs the at_exit hook and spawns the flush thread" do
        start

        expect(described_class.instance_variable_get(:@at_exit_installed)).to be(true)
        expect(described_class.instance_variable_get(:@thread)).to be_a(Thread)
      end

      # Sampling is what needs `Coverage.suspend`; the full rate never
      # suspends anything, so an older runtime measures fine.
      it "measures at the full rate on a runtime that cannot suspend" do
        allow(Coverage).to receive(:respond_to?).and_call_original
        allow(Coverage).to receive(:respond_to?).with(:suspend).and_return(false)

        expect(start).to be true
      end

      # Before `Coverage.supported?` existed there was nothing to ask,
      # and oneshot lines were there to be used.
      it "assumes oneshot lines on a runtime that cannot be asked" do
        allow(Coverage).to receive(:respond_to?).and_call_original
        allow(Coverage).to receive(:respond_to?).with(:supported?).and_return(false)
        allow(Coverage).to receive(:supported?).and_raise(NoMethodError)

        expect(start).to be true
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

      it "rejects a negative or non-numeric flush jitter" do
        expect { start(flush_jitter: -1) }.to raise_error(SimpleCov::Production::Error, /flush_jitter/)
        expect { start(flush_jitter: "6") }.to raise_error(SimpleCov::Production::Error, /flush_jitter/)
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
      # The out-of-root file leads: a drain that gave up on the first
      # file it could not place would lose everything behind it.
      stub_coverage(result: {
                      File.expand_path("/elsewhere/b.rb") => {oneshot_lines: [7]},
                      abs("lib/quiet.rb") => {oneshot_lines: []},
                      abs("lib/a.rb") => {oneshot_lines: [3, 1]}
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

    # The message half of the expectation comes from the error itself,
    # because each platform words its strerror differently.
    it "names the failure the sink raised, class and message" do
      error = Errno::ECONNREFUSED.new("the sink")
      allow(sink).to receive(:store).and_raise(error)

      stderr = capture_stderr { described_class.flush }

      expect(stderr).to eq("[SimpleCov::Production] flush failed " \
                           "(Errno::ECONNREFUSED: #{error.message}); " \
                           "retrying next interval\n")
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

    # Every drain and delivery happens under the same lock the flush
    # thread takes, so a forced flush and the scheduled one cannot
    # interleave halfway through a delta.
    it "drains and delivers under the lock" do
      held = []
      allow(described_class).to receive(:pull_pending) { held << mutex.owned? }
      allow(described_class).to receive(:push_pending) { held << mutex.owned? }

      described_class.flush

      expect(held).to eq([true, true])
    end

    it "reports an empty flush as a success without touching the sink" do
      allow(Coverage).to receive(:result).and_return({})
      expect(described_class.flush).to be true
      expect(sink).not_to have_received(:store)
    end
  end

  # The runtime reports one entry per file it loaded, most of them with
  # nothing to say, and a file it reports without oneshot lines at all
  # must not take the rest of the drain down with it.
  describe "what a drain skips" do
    before { stub_coverage }

    it "skips a file with no oneshot lines and keeps draining the rest" do
      start
      allow(Coverage).to receive(:result).and_return(
        abs("lib/silent.rb") => {},
        abs("lib/empty.rb") => {oneshot_lines: []},
        abs("lib/a.rb") => {oneshot_lines: [1]}
      )

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

  # Not `describe ".running?"`: naming the method there would narrow
  # the mutation testing pool for it to these two examples alone.
  describe "what counts as running" do
    it "answers false, not nil, before anything has started" do
      # Untouched in a process that never started production mode, which
      # earlier examples here have long since left behind.
      described_class.instance_variable_set(:@running, nil)

      expect(described_class.running?).to be(false)
    end

    # A forked child inherits the flag but not the flush thread, so the
    # measurement belongs to the process that recorded itself against it
    # until that child starts its own.
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

    it "runs under a name a process listing can explain" do
      stub_coverage
      start

      thread = described_class.instance_variable_get(:@thread)
      expect(thread).to be_a(Thread)
      expect(thread.name).to eq("SimpleCov::Production flusher")
    end

    # The whole point of waiting on a condition variable rather than
    # sleeping: `stop` on a deploy must not sit out a ten-minute
    # interval before the process can exit.
    it "is woken by stop rather than waiting out the interval" do
      stub_coverage
      described_class.start(root: root, sink: queue_sink, flush_interval: 600)
      thread = sleeping_flush_thread

      Timeout.timeout(10) { described_class.stop }

      expect(thread).not_to be_alive
    end

    # Woken to stop, the thread stops: one more drain on the way out
    # would deliver the same lines twice.
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

    # Signalling without the lock is how a wake goes missing: the thread
    # can be between checking its state and waiting when the signal
    # lands, and would then sit out a full interval.
    it "signals under the lock" do
      held = nil
      waiter = described_class.instance_variable_get(:@waiter)
      allow(waiter).to receive(:signal).and_wrap_original do |original|
        held = mutex.owned?
        original.call
      end

      described_class.send(:wake_flush_thread)

      expect(held).to be(true)
    end
  end

  # The jitter keeps a fleet of workers booted together (a forking
  # server's worker-boot hook starts them all at once) from draining
  # into the shared sink at the same instant every interval.
  describe "flush jitter" do
    before { stub_coverage }

    it "waits the interval plus a fresh random share of the jitter" do
      start_without_flush_thread(flush_jitter: 60)
      allow(described_class).to receive(:rand).and_return(0.5)

      expect(described_class.send(:next_wait)).to eq(630)
    end

    it "defaults the jitter to a tenth of the flush interval" do
      start_without_flush_thread
      allow(described_class).to receive(:rand).and_return(1.0)

      expect(described_class.send(:next_wait)).to eq(660)
    end

    it "waits exactly the interval when the jitter is zero" do
      start(flush_jitter: 0)

      expect(described_class.send(:next_wait)).to eq(600)
    end
  end

  # Each keyword configures one thing, and the defaults are part of the
  # documented interface, so both are read back off the configured state
  # rather than inferred from behaviour.
  describe "what start configures",
           mutant_expression: ["SimpleCov::Production*", "SimpleCov::Production.start"] do
    before { stub_coverage }

    def configured(name)
      described_class.instance_variable_get(:"@#{name}")
    end

    it "carries every keyword through to the configured state" do
      described_class.start(root: root, sink: sink, flush_interval: 30, flush_jitter: 7,
                            sample_rate: 0.25, max_buffered_lines: 42)

      expect(configured(:sink)).to be(sink)
      expect(configured(:flush_interval)).to eq(30)
      expect(configured(:flush_jitter)).to eq(7)
      expect(configured(:sample_rate)).to eq(0.25)
      expect(configured(:max_buffered_lines)).to eq(42)
      expect(configured(:root_prefix)).to eq(File.expand_path(root) + File::SEPARATOR)
    end

    it "applies the documented defaults for everything left out" do
      described_class.start(root: root, sink: sink)

      expect(configured(:flush_interval)).to eq(60)
      expect(configured(:flush_jitter)).to eq(6.0)
      expect(configured(:sample_rate)).to eq(1.0)
      expect(configured(:max_buffered_lines)).to eq(1_000_000)
    end

    it "measures from the first interval and takes the process it started in" do
      # A forked worker inherits its parent's buffer along with
      # everything else, and those lines are the parent's to deliver.
      described_class.instance_variable_set(:@pending, {"lib/parent.rb" => Set[1]})
      start

      expect(configured(:measuring)).to be true
      expect(configured(:pid)).to eq(Process.pid)
      expect(configured(:pending)).to eq({})
    end

    # A deploy script hands over whatever it has, and a worker that
    # chdirs later must still recognise the same files.
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

  # `reset!` is what lets a test suite run this module repeatedly, so
  # every piece of state it claims to clear is checked.
  describe ".reset!" do
    before { stub_coverage }

    it "clears the running state, the process, the buffer, and the thread" do
      start
      described_class.instance_variable_set(:@pending, {"lib/a.rb" => Set[1]})

      described_class.reset!

      expect(described_class).not_to be_running
      expect(described_class.instance_variable_get(:@running)).to be false
      expect(described_class.instance_variable_get(:@pid)).to be_nil
      expect(described_class.instance_variable_get(:@pending)).to eq({})
      expect(described_class.instance_variable_get(:@thread)).to be_nil
      expect(described_class.instance_variable_get(:@started_coverage)).to be false
    end

    # One hook per process: the registration flag deliberately survives,
    # so a second start after a reset does not stack another at_exit.
    it "leaves the at_exit registration in place" do
      start
      described_class.reset!

      expect(described_class.instance_variable_get(:@at_exit_installed)).to be true
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
      # The state a first start finds, which earlier examples in this
      # process have left behind: nothing configured, so no lock to take
      # and no thread to wake.
      described_class.instance_variable_set(:@mutex, nil)

      expect { described_class.reset! }.not_to raise_error
    end
  end

  describe "the sampling duty cycle" do
    before { stub_coverage }

    # At the full rate there is nothing to sample, so the runtime is
    # never touched: exactly 1.0 measures always.
    it "never suspends or resumes at the full rate" do
      start_without_flush_thread(sample_rate: 1.0)
      allow(described_class).to receive(:rand).and_return(0.99)

      described_class.send(:cycle)

      expect(Coverage).not_to have_received(:suspend)
      expect(Coverage).not_to have_received(:resume)
    end

    it "does not even draw a sample at the full rate" do
      start_without_flush_thread(sample_rate: 1.0)
      allow(described_class).to receive(:rand).and_call_original

      described_class.send(:cycle)

      expect(described_class).not_to have_received(:rand)
    end

    it "records the state each cycle settled on" do
      start_without_flush_thread(sample_rate: 0.5)
      allow(described_class).to receive(:rand).and_return(0.9)
      described_class.send(:cycle)
      expect(described_class.instance_variable_get(:@measuring)).to be false

      allow(described_class).to receive(:rand).and_return(0.1)
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

  # A child that inherits a measurement from its parent keeps it: the
  # fork only needs its own flush thread, not a second Coverage owner.
  describe "starting in a forked child", mutant_expression: ["SimpleCov::Production*",
                                                             "SimpleCov::Production.start"] do
    it "picks the inherited measurement back up" do
      stub_coverage
      start
      described_class.instance_variable_set(:@pid, Process.pid - 1)
      described_class.instance_variable_set(:@running, false)
      allow(Coverage).to receive(:running?).and_return(true)

      expect(start).to be true
      expect(Coverage).to have_received(:start).once
    end

    it "still declines a running Coverage it did not start itself" do
      stub_coverage
      described_class.instance_variable_set(:@started_coverage, false)
      allow(Coverage).to receive(:running?).and_return(true)

      stderr = capture_stderr { expect(start).to be false }
      expect(stderr).to include("Coverage is already running")
    end

    # All three conditions have to hold to inherit a measurement: this
    # module started it, in some process, and not this one. Each is
    # checked by making it the only one that fails.
    it "declines a measurement it started in this very process" do
      stub_coverage
      described_class.instance_variable_set(:@started_coverage, true)
      described_class.instance_variable_set(:@pid, Process.pid)
      allow(Coverage).to receive(:running?).and_return(true)

      stderr = capture_stderr { expect(start).to be false }
      expect(stderr).to include("Coverage is already running")
    end

    it "declines a measurement with no process recorded against it" do
      stub_coverage
      described_class.instance_variable_set(:@started_coverage, true)
      described_class.instance_variable_set(:@pid, nil)
      allow(Coverage).to receive(:running?).and_return(true)

      stderr = capture_stderr { expect(start).to be false }
      expect(stderr).to include("Coverage is already running")
    end

    it "declines another tool's measurement even from a different process" do
      stub_coverage
      described_class.instance_variable_set(:@started_coverage, false)
      described_class.instance_variable_set(:@pid, Process.pid - 1)
      allow(Coverage).to receive(:running?).and_return(true)

      stderr = capture_stderr { expect(start).to be false }
      expect(stderr).to include("Coverage is already running")
    end
  end

  # The at_exit hook is registered once per process and carries nothing
  # but a call to `stop`, which declines on its own when nothing is
  # running. The registration itself is asserted by standing in for
  # `at_exit`.
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
      expect(described_class.instance_variable_get(:@at_exit_installed)).to be true
    end

    it "stops production coverage when the hook fires" do
      hook = nil
      allow(described_class).to receive(:at_exit) { |&block| hook = block }
      described_class.send(:install_at_exit)
      allow(described_class).to receive(:stop)

      hook.call

      expect(described_class).to have_received(:stop)
    end
  end
end
