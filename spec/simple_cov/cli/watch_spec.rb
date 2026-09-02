# frozen_string_literal: true

require "helper"
require "net/http"
require "simplecov/cli"
require "socket"
require "support/cli_context"
require "timeout"
require "tmpdir"

RSpec.describe SimpleCov::CLI do
  include_context "a CLI"

  describe "watch subcommand", mutant_expression: "SimpleCov::CLI::Watch*" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-watch-spec-") }
    let(:coverage_dir) { File.join(tmp, "coverage") }
    let(:json_path) { File.join(coverage_dir, "coverage.json") }
    let(:log_path) { File.join(tmp, "runs.log") }
    let(:code_path) { File.join(tmp, "lib/code.rb") }

    after { FileUtils.rm_rf(tmp) }

    def write_report(percent: 90.0, contexts: ["spec/code_spec.rb:1"], tables: {"0" => "1"})
      FileUtils.mkdir_p(coverage_dir)
      document = {"coverage" => {code_path => {"lines" => [1], "contexts" => tables}}}
      document["total"] = {"lines" => {"percent" => percent}} if percent
      document["contexts"] = contexts if contexts
      File.write(json_path, JSON.dump(document))
      File.write(File.join(coverage_dir, "index.html"), "<html>report</html>")
    end

    def fake_suite(percent: 95.0)
      total = percent ? %(document["total"] = {"lines" => {"percent" => #{percent}}}) : %(document.delete("total"))
      script = File.join(tmp, "suite.rb")
      File.write(script, <<~RUBY)
        require "json"
        line = "args=\#{ARGV.join(',')} window=\#{ENV['SIMPLECOV_MERGE_TIMEOUT']}"
        File.open(#{log_path.inspect}, "a") { |log| log.puts(line) }
        document = JSON.parse(File.read(#{json_path.inspect}))
        #{total}
        File.write(#{json_path.inspect}, JSON.dump(document))
      RUBY
      [RbConfig.ruby, script]
    end

    def announced_port
      %r{serving http://127\.0\.0\.1:(\d+)/}
    end

    def start_watch(*argv)
      thread = Thread.new { Dir.chdir(tmp) { run("watch", "--interval", "0.05", *argv) } }
      wait_for { stdout.string.match?(announced_port) }
      [thread, stdout.string[announced_port, 1].to_i]
    end

    def stop_watch(thread)
      thread.raise(Interrupt) if thread.alive?
      thread.join(5)
    end

    def wait_timeout
      (RUBY_ENGINE == "ruby") ? 10 : 60
    end

    def wait_for
      Timeout.timeout(wait_timeout) do
        sleep(0.05) until yield
      end
    end

    def wait_for_log
      wait_for { File.exist?(log_path) && File.read(log_path).include?("window=") }
    end

    def touch_code
      FileUtils.mkdir_p(File.dirname(code_path))
      File.write(code_path, "# changed #{rand}\n")
      FileUtils.touch(code_path, mtime: Time.now + 2)
    end

    before do
      allow(described_class).to receive(:coverage_dir).and_return(coverage_dir)
      FileUtils.mkdir_p(File.dirname(code_path))
      File.write(code_path, "# original\n")
      FileUtils.mkdir_p(File.join(tmp, "spec"))
      File.write(File.join(tmp, "spec/code_spec.rb"), "# spec\n")
    end

    it "reruns the recorded tests for a changed file and reloads the report" do
      expect(watched_through_a_change).to match(
        log: a_string_including("args=spec/code_spec.rb window=86400"),
        event: a_string_including("data: reload"),
        announced: a_string_matching(/watching 2 files, serving http:\/\/127\.0\.0\.1:\d+\//)
      )
    end

    # Watches through one change, answering the log the rerun wrote, the event
    # the browser was sent, and what the watcher announced.
    def watched_through_a_change
      write_report
      thread, port = start_watch(*fake_suite)
      begin
        events = TCPSocket.new("127.0.0.1", port)
        events.write("GET /events HTTP/1.1\r\nHost: x\r\n\r\n")
        wait_for { events.readline.strip.empty? }
        touch_code
        wait_for_log
        log = File.read(log_path)
        event = Timeout.timeout(wait_timeout) { events.readline }
        wait_for { stdout.string.include?("lib/code.rb changed, running 1 file... 95.00% (+5.00%)") }
      ensure
        events&.close
        stop_watch(thread)
      end
      {log: log, event: event, announced: stdout.string}
    end

    it "serves the report with the reload listener injected" do
      expect(watched_and_served).to match(
        code: "200",
        body: a_string_including("<html>report</html>").and(a_string_including("EventSource('/events')")),
        on_disk: "<html>report</html>"
      )
    end

    def watched_and_served
      write_report
      thread, port = start_watch(*fake_suite)
      begin
        response = Net::HTTP.start("127.0.0.1", port, open_timeout: 5, read_timeout: 5) { |http| http.get("/") }
        {code: response.code, body: response.body, on_disk: File.read(File.join(coverage_dir, "index.html"))}
      ensure
        stop_watch(thread)
      end
    end

    it "runs the full command when the report carries no test map" do
      expect(watched_without_a_test_map).to include("args= ")
    end

    def watched_without_a_test_map
      write_report(contexts: nil, tables: nil)
      thread, = start_watch(*fake_suite)
      begin
        touch_code
        wait_for_log
        wait_for { stdout.string.include?("running the full suite") }
        File.read(log_path)
      ensure
        stop_watch(thread)
      end
    end

    it "notes a change no recorded test touches without running anything" do
      write_report(tables: {})
      watch_through_a_change { stdout.string.include?("no recorded test touches it") }

      expect(File.exist?(log_path)).to be(false)
    end

    # Starts the watcher, touches the code, and waits for the condition the
    # example is about before stopping it again.
    def watch_through_a_change(*extra, percent: 95.0, &settled)
      thread, = start_watch(*extra, *fake_suite(percent: percent))
      begin
        touch_code
        wait_for(&settled)
      ensure
        stop_watch(thread)
      end
    end

    it "builds the initial report by running the command once when it is missing" do
      expect(watched_without_a_report).to match(log: a_string_including("args= "),
        announced: a_string_including("watching 1 file, serving"))
    end

    def watched_without_a_report
      FileUtils.mkdir_p(coverage_dir)
      File.write(File.join(coverage_dir, "index.html"), "<html>report</html>")
      command = fake_suite
      File.write(File.join(tmp, "suite.rb"), <<~RUBY + File.read(File.join(tmp, "suite.rb")))
        require "json"
        require "fileutils"
        FileUtils.mkdir_p(#{coverage_dir.inspect})
        File.write(#{json_path.inspect}, JSON.dump(
          "total" => {"lines" => {"percent" => 90.0}},
          "coverage" => {#{code_path.inspect} => {"lines" => [1]}}
        ))
      RUBY
      stop_watch(start_watch(*command).first)
      {log: File.read(log_path), announced: stdout.string}
    end

    it "reports the new percentage without a delta when the report had no baseline" do
      write_report(percent: nil, contexts: nil, tables: nil)
      watch_through_a_change { stdout.string.include?("running the full suite... 95.00%\n") }

      expect(stdout.string).not_to include("(+")
    end

    it "ends the result line bare when the regenerated report has no totals" do
      write_report(contexts: nil, tables: nil)
      watch_through_a_change(percent: nil) { stdout.string.include?("running the full suite...\n") }

      expect(stdout.string).not_to include("%\n")
    end

    it "says so when the run leaves the report unreadable" do
      write_report(contexts: nil, tables: nil)
      File.write(breaker, "File.write(#{json_path.inspect}, '{')")
      watch_running(RbConfig.ruby, breaker) { stdout.string.include?("the report did not regenerate") }

      expect(stderr.string).to include("isn't valid JSON")
    end

    def breaker
      File.join(tmp, "break.rb")
    end

    def watch_running(*command, &settled)
      thread, = start_watch(*command)
      begin
        touch_code
        wait_for(&settled)
      ensure
        stop_watch(thread)
      end
    end

    it "reports the primary criterion's percent when the report names one" do
      session = described_class::Watch::Session.new(command: ["true"], dir: coverage_dir,
        interval: 0.01, stdout: stdout, stderr: stderr)
      session.instance_variable_set(:@document, branch_primary_document)

      expect(session.send(:total_percent)).to eq(75.0)
    end

    def branch_primary_document
      {"meta" => {"primary_coverage" => "branch"},
       "total" => {"lines" => {"percent" => 90.0}, "branches" => {"percent" => 75.0}}}
    end

    it "collects an editor's save burst into one run" do
      session = described_class::Watch::Session.new(command: ["true"], dir: coverage_dir,
        interval: 0.01, stdout: stdout, stderr: stderr)
      scripted = Struct.new(:sequence) { def changes = sequence.shift || [] }
      session.instance_variable_set(:@poller, scripted.new([["a.rb"], ["b.rb"], []]))
      expect(session.send(:settled_changes)).to eq(["a.rb", "b.rb"])
    end

    describe ".parse" do
      it "asks for an ephemeral port on the loopback address by default" do
        opts, = described_class::Watch.parse(%w[rake])
        expect(opts).to eq(port: 0, host: "127.0.0.1", interval: 0.5, open: false)
      end

      it "takes each flag when it is given" do
        opts, = described_class::Watch.parse(%w[--port 9 --host ::1 --interval 2.5 --open rake test])

        expect(opts).to eq(port: 9, host: "::1", interval: 2.5, open: true)
      end

      it "leaves the command it is to run behind them" do
        _opts, rest = described_class::Watch.parse(%w[--port 9 --host ::1 --interval 2.5 --open rake test])

        expect(rest).to eq(%w[rake test])
      end
    end

    it "errors without a command, pointing at what one looks like" do
      exited!(1, run("watch"))

      expect(stderr.string).to eq("simplecov watch: missing command to run " \
                                  "(e.g. `simplecov watch bundle exec rspec`)\n")
    end

    context "when the port is already taken" do
      def watch_a_taken_port
        write_report
        allow(described_class::Serve).to receive(:require_socket).and_call_original
        blocker = TCPServer.new("127.0.0.1", 0)
        Dir.chdir(tmp) { run("watch", "--port", blocker.addr[1].to_s, "ruby", "-e", "1") }
      ensure
        blocker.close
      end

      it "errors" do
        expect(watch_a_taken_port).to eq(1)
      end

      it "names the host and the port it could not bind" do
        watch_a_taken_port

        expect(stderr.string).to match(/\Asimplecov watch: cannot bind to 127\.0\.0\.1:\d+ \(\S.*\)\n\z/)
      end

      it "requires socket for itself" do
        watch_a_taken_port

        expect(described_class::Serve).to have_received(:require_socket)
      end
    end

    it "exits non-zero when the initial run produces no report" do
      expect(Dir.chdir(tmp) { run("watch", RbConfig.ruby, "-e", "0") }).to eq(1)
    end

    it "says what it could not find" do
      Dir.chdir(tmp) { run("watch", RbConfig.ruby, "-e", "0") }

      expect(stderr.string).to include("not found")
    end

    it "reads its own flag out of the argument list" do
      opts, = described_class::Watch.parse(["--interval", "1", "bundle", "exec", "rspec", "--seed", "1"])

      expect(opts[:interval]).to eq(1.0)
    end

    it "leaves the runner's own flags alone" do
      _opts, command = described_class::Watch.parse(["--interval", "1", "bundle", "exec", "rspec", "--seed", "1"])

      expect(command).to eq(["bundle", "exec", "rspec", "--seed", "1"])
    end

    it "opens the served report in the browser under --open" do
      opened_port, served_port = opened_under_open

      expect(opened_port).to eq(served_port)
    end

    def opened_under_open
      write_report
      opened = Queue.new
      allow(described_class::Watch).to receive(:launch_browser) { |server, _stderr| opened << server.addr[1] }
      thread, port = start_watch("--open", *fake_suite)
      begin
        [Timeout.timeout(10) { opened.pop }, port]
      ensure
        stop_watch(thread)
      end
    end

    context "with a platform opener" do
      before do
        server = instance_double(TCPServer, addr: ["AF_INET", 53_422, "localhost", "127.0.0.1"])
        allow(described_class::Open).to receive(:browser_opener).and_return(["fake-open"])
        allow(described_class::Watch).to receive(:spawn).and_return(4242)
        allow(Process).to receive(:detach)
        described_class::Watch.launch_browser(server, stderr)
      end

      it "hands the report URL to it" do
        expect(described_class::Watch).to have_received(:spawn)
          .with("fake-open", "http://127.0.0.1:53422/", out: File::NULL, err: File::NULL)
      end

      it "detaches the process it spawned" do
        expect(Process).to have_received(:detach).with(4242)
      end
    end

    it "brackets an IPv6 address in the URL it opens" do
      launch_browser_for("AF_INET6", "::1")

      expect(described_class::Watch).to have_received(:spawn)
        .with("fake-open", "http://[::1]:53422/", out: File::NULL, err: File::NULL)
    end

    def launch_browser_for(family, address)
      server = instance_double(TCPServer, addr: [family, 53_422, "localhost", address])
      allow(described_class::Open).to receive(:browser_opener).and_return(["fake-open"])
      allow(described_class::Watch).to receive(:spawn).and_return(4242)
      allow(Process).to receive(:detach)
      described_class::Watch.launch_browser(server, stderr)
    end

    context "with no known opener for the platform" do
      before do
        server = instance_double(TCPServer, addr: ["AF_INET", 53_422, "localhost", "127.0.0.1"])
        allow(described_class::Open).to receive(:browser_opener).and_return(nil)
        allow(described_class::Watch).to receive(:spawn)
        allow(Process).to receive(:detach)
        described_class::Watch.launch_browser(server, stderr)
      end

      it "spawns nothing" do
        expect(described_class::Watch).not_to have_received(:spawn)
      end

      it "detaches nothing" do
        expect(Process).not_to have_received(:detach)
      end

      it "degrades to a note naming the URL" do
        expect(stderr.string).to eq("simplecov watch: no known browser opener for this platform, " \
                                    "open it yourself: http://127.0.0.1:53422/\n")
      end
    end

    describe ".serve_session" do
      let(:listener) { TCPServer.new("127.0.0.1", 0) }
      let(:session) { instance_double(described_class::Watch::Session, run: 7) }

      before do
        allow(described_class::Watch).to receive_messages(session_for: session, launch_browser: nil)
      end

      after { listener.close unless listener.closed? }

      context "when it serves a session" do
        let(:opts) { {open: false, interval: 0.25} }
        let(:status) { described_class::Watch.serve_session(listener, %w[rake test], opts, stdout, stderr) }

        it "answers the session's status" do
          expect(status).to eq(7)
        end

        it "builds the session from what it was given" do
          status

          expect(described_class::Watch).to have_received(:session_for).with(%w[rake test], opts, stdout, stderr)
        end

        it "runs it against the listener" do
          status

          expect(session).to have_received(:run).with(listener)
        end

        it "opens no browser without --open" do
          status

          expect(described_class::Watch).not_to have_received(:launch_browser)
        end

        it "closes the listener behind it" do
          status

          expect(listener).to be_closed
        end
      end

      it "opens the browser on the listener under --open" do
        described_class::Watch.serve_session(listener, %w[rake], {open: true}, stdout, stderr)

        expect(described_class::Watch).to have_received(:launch_browser).with(listener, stderr)
      end

      it "lets an exception out of the session" do
        allow(session).to receive(:run).and_raise("boom")

        expect { described_class::Watch.serve_session(listener, %w[rake], {open: false}, stdout, stderr) }
          .to raise_error("boom")
      end

      it "closes the listener even when the session raises" do
        allow(session).to receive(:run).and_raise("boom")
        suppress(RuntimeError) do
          described_class::Watch.serve_session(listener, %w[rake], {open: false}, stdout, stderr)
        end

        expect(listener).to be_closed
      end
    end

    describe SimpleCov::CLI::Watch::Poller do
      let(:poller) { described_class.new }
      let(:file) { File.join(tmp, "a.rb") }

      it "watches nothing until it is given paths" do
        expect(poller.size).to eq(0)
      end

      it "reports no change until then either" do
        expect(poller.changes).to eq([])
      end

      it "reports nothing while mtimes hold still" do
        File.write(file, "a")
        poller.watch([file])
        expect(poller.changes).to eq([])
      end

      it "reports a touched file" do
        File.write(file, "a")
        poller.watch([file])
        FileUtils.touch(file, mtime: Time.now + 2)

        expect(poller.changes).to eq([file])
      end

      it "reports it once per change, not once per poll" do
        File.write(file, "a")
        poller.watch([file])
        FileUtils.touch(file, mtime: Time.now + 2)
        poller.changes

        expect(poller.changes).to eq([])
      end

      it "reports the path whose mtime moved, and only that one" do
        other = watch_two_files
        FileUtils.touch(other, mtime: Time.now + 2)

        expect(poller.changes).to eq([other])
      end

      it "reports every path whose mtime moved" do
        other = watch_two_files
        FileUtils.touch([file, other], mtime: Time.now + 4)

        expect(poller.changes).to eq([file, other])
      end

      def watch_two_files
        other = File.join(tmp, "b.rb")
        File.write(file, "a")
        File.write(other, "b")
        poller.watch([file, other])
        other
      end

      it "reports a vanished file" do
        File.write(file, "a")
        poller.watch([file])
        File.delete(file)

        expect(poller.changes).to eq([file])
      end

      it "reports it appearing again" do
        watch_and_delete
        File.write(file, "b")

        expect(poller.changes).to eq([file])
      end

      def watch_and_delete
        File.write(file, "a")
        poller.watch([file])
        File.delete(file)
        poller.changes
      end
    end

    describe SimpleCov::CLI::Watch::Narrator do
      let(:narrator) { described_class.new(stdout, "/root") }

      def server_at(host)
        instance_double(TCPServer, addr: ["AF_INET", 4321, "localhost", host])
      end

      it "counts the watched files, and says one in the singular" do
        narrator.banner(server_at("127.0.0.1"), 1)
        expect(stdout.string).to eq("watching 1 file, serving http://127.0.0.1:4321/\nPress Ctrl-C to stop.\n")
      end

      it "brackets an IPv6 address so the URL parses" do
        narrator.banner(server_at("::1"), 2)
        expect(stdout.string).to eq("watching 2 files, serving http://[::1]:4321/\nPress Ctrl-C to stop.\n")
      end

      it "names a burst by its first file and counts the rest" do
        narrator.change(["/root/a.rb", "/root/b.rb", "/root/c.rb"],
          {run: true, tests: ["spec/a_spec.rb", "spec/b_spec.rb"]})
        expect(stdout.string).to eq("a.rb and 2 more changed, running 2 files...")
      end

      it "names a lone change by itself" do
        narrator.change(["/root/a.rb"], {run: true, tests: nil})
        expect(stdout.string).to eq("a.rb changed, running the full suite...")
      end

      it "says it is stopping, on a line of its own" do
        narrator.stopping
        expect(stdout.string).to eq("\nsimplecov watch: stopping\n")
      end
    end

    describe SimpleCov::CLI::Watch::TestPlan do
      def plan(document, changed = ["lib/a.rb"])
        described_class.build(changed, document, root: "/proj", input: "coverage.json", stderr: stderr)
      end

      [["spec/a_spec.rb:1", 42], "junk"].each do |contexts|
        it "runs everything for #{contexts.inspect} in place of a context list" do
          expect(plan("contexts" => contexts)).to eq(run: true, tests: nil)
        end
      end

      it "runs everything when the report has no map at all" do
        expect(plan({})).to eq(run: true, tests: nil)
      end

      it "runs nothing when no recorded test touches the change" do
        document = {"contexts" => ["spec/a_spec.rb:1"],
                    "coverage" => {File.expand_path("/proj/lib/b.rb") => {"lines" => [1]}}}
        expect(plan(document, ["lib/b.rb"])).to eq(run: false, tests: [])
      end

      it "fails open to the full command on a selection trigger" do
        expect(plan_with_a_ghost_test).to eq(run: true, tests: nil)
      end

      it "says nothing about the trigger" do
        plan_with_a_ghost_test

        expect(stderr.string).to be_empty
      end

      def plan_with_a_ghost_test
        document = {
          "contexts" => ["spec/ghost_spec.rb:1"],
          "coverage" => {File.join(tmp, "lib/code.rb") => {"lines" => [1], "contexts" => {"0" => "1"}}}
        }
        Dir.chdir(tmp) do
          described_class.build(["lib/code.rb"], document, root: tmp, input: "coverage.json", stderr: stderr)
        end
      end

      it "derives the watch set without a coverage section" do
        paths = described_class.watched_paths({"contexts" => ["spec/a_spec.rb:1"]}, tmp)
        expect(paths).to eq([File.join(tmp, "spec/a_spec.rb")])
      end

      it "runs everything for a change the report has no data for" do
        expect(plan({"contexts" => ["spec/a_spec.rb:1"], "coverage" => {}}, ["README.md"]))
          .to eq(run: true, tests: nil)
      end

      it "runs everything when the report's coverage section is malformed" do
        expect(plan("contexts" => ["spec/a_spec.rb:1"], "coverage" => "junk")).to eq(run: true, tests: nil)
      end

      it "says what was malformed" do
        plan("contexts" => ["spec/a_spec.rb:1"], "coverage" => "junk")

        expect(stderr.string).to eq(
          %(simplecov affected: input file "coverage.json" isn't valid JSON ("coverage" must be an object)\n)
        )
      end

      it "runs just the recorded tests that touch the change" do
        document = {"contexts" => ["spec/code_spec.rb:1"],
                    "coverage" => {File.join(tmp, "lib/code.rb") => {"lines" => [1], "contexts" => {"0" => "1"}}}}

        built = described_class.build(["lib/code.rb"], document, root: tmp, input: "coverage.json", stderr: stderr)

        expect(built).to eq(run: true, tests: ["spec/code_spec.rb"])
      end

      it "derives the watch set from the report's own paths" do
        document = {"coverage" => {"/x/a.rb" => {}, File.join(tmp, "spec/a_spec.rb") => {}},
                    "contexts" => ["spec/a_spec.rb:1", 42]}

        expect(described_class.watched_paths(document, tmp))
          .to eq(["/x/a.rb", File.join(tmp, "spec/a_spec.rb")])
      end

      it "watches nothing a malformed report names" do
        expect(described_class.watched_paths({"coverage" => "junk", "contexts" => "junk"}, tmp)).to eq([])
      end
    end

    describe SimpleCov::CLI::Watch::LiveReport do
      it "drops a departed tab's queue after a failed write" do
        expect(queues_after_a_departed_tab).to be_empty
      end

      def queues_after_a_departed_tab
        live = described_class.new(tmp)
        server = TCPServer.new("127.0.0.1", 0)
        client = TCPSocket.new("127.0.0.1", server.addr[1])
        served = server.accept
        thread = Thread.new { live.send(:stream, served) }
        wait_for { live.instance_variable_get(:@queues).size == 1 }
        wait_for { client.readline.strip.empty? }
        served.close
        live.broadcast
        thread.join(5)
        live.instance_variable_get(:@queues)
      ensure
        client&.close
        server&.close
      end

      it "opens the stream with SSE headers and forwards every broadcast" do
        expect(streamed_broadcasts).to eq(
          header: "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n" \
                  "Cache-Control: no-cache\r\n\r\n",
          events: ["data: reload\n", "\n", "data: again\n", "\n"]
        )
      end

      # Streams to one live tab, answering the header it opened with and the
      # events it forwarded.
      def streamed_broadcasts
        live = described_class.new(tmp)
        server = TCPServer.new("127.0.0.1", 0)
        client = TCPSocket.new("127.0.0.1", server.addr[1])
        served = server.accept
        thread = Thread.new { live.send(:stream, served) }
        wait_for { live.instance_variable_get(:@queues).size == 1 }
        header = +""
        header << client.readline until header.end_with?("\r\n\r\n")
        live.broadcast
        live.broadcast("again")
        events = Timeout.timeout(10) { Array.new(4) { client.readline } }
        served.close
        live.broadcast
        thread.join(5)
        {header: header, events: events}
      ensure
        client&.close
        server&.close
      end

      it "hands every open tab the event it was given, and a reload by default" do
        queues = [Queue.new, Queue.new]
        broadcast_to(queues)

        expect(queues.collect { |queue| Array.new(2) { queue.pop(true) } })
          .to eq([%w[reload again], %w[reload again]])
      end

      def broadcast_to(queues)
        live = described_class.new(tmp)
        live.instance_variable_set(:@queues, queues)
        live.broadcast
        live.broadcast("again")
      end

      it "mounts the stream and the live page" do
        live = described_class.new(tmp)

        expect(live.routes.keys).to eq(["/events", "/", "/index.html"])
      end

      it "mounts the live page on both index paths" do
        live = described_class.new(tmp)

        expect(live.routes["/"]).to eq(live.routes["/index.html"])
      end

      it "serves the report page as HTML" do
        File.write(File.join(tmp, "index.html"), "<html>report</html>")

        expect(served_live("GET /index.html HTTP/1.1"))
          .to start_with("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n")
      end

      it "appends the reload listener to it" do
        File.write(File.join(tmp, "index.html"), "<html>report</html>")

        expect(served_live("GET /index.html HTTP/1.1"))
          .to end_with("<html>report</html>#{described_class::RELOAD_SCRIPT}")
      end

      def served_live(request_line)
        live = described_class.new(tmp)
        server = TCPServer.new("127.0.0.1", 0)
        thread = Thread.new do
          SimpleCov::CLI::Serve::StaticFileHandler.handle_connection(server.accept, tmp, live.routes)
        end
        sock = TCPSocket.new("127.0.0.1", server.addr[1])
        sock.write("#{request_line}\r\nHost: x\r\n\r\n")
        Timeout.timeout(10) { sock.read }
      ensure
        sock&.close
        thread&.join(2)
        server&.close
      end

      it "answers 404 for the page before a report exists" do
        expect(served_live("GET / HTTP/1.1")).to start_with("HTTP/1.1 404")
      end
    end
  end

  describe SimpleCov::CLI::Watch::Session, mutant_expression: "SimpleCov::CLI::Watch::Session*" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-watch-spec-") }
    let(:session) do
      described_class.new(command: %w[true], dir: tmp, interval: 0, stdout: stdout, stderr: stderr)
    end

    let(:poller) { instance_double(SimpleCov::CLI::Watch::Poller) }

    before { session.instance_variable_set(:@poller, poller) }
    after { FileUtils.rm_rf(tmp) }

    describe "#settled_changes" do
      it "answers nothing when nothing changed" do
        allow(poller).to receive(:changes).and_return([])

        expect(session.send(:settled_changes)).to eq([])
      end

      it "answers at once, without looking again" do
        allow(poller).to receive(:changes).and_return([])
        session.send(:settled_changes)

        expect(poller).to have_received(:changes).once
      end

      it "collects a burst until an interval brings nothing new" do
        allow(poller).to receive(:changes).and_return(["a.rb"], ["b.rb"], ["a.rb"], [])
        expect(session.send(:settled_changes)).to eq(%w[a.rb b.rb])
      end

      it "answers the change it settled on" do
        expect(settled_after_waiting.first).to eq(["a.rb"])
      end

      it "waits an interval before looking again" do
        expect(settled_after_waiting.last).to be >= 0.05
      end

      def settled_after_waiting
        waiting = described_class.new(command: %w[true], dir: tmp, interval: 0.05,
          stdout: stdout, stderr: stderr)
        waiting.instance_variable_set(:@poller, poller)
        allow(poller).to receive(:changes).and_return(["a.rb"], [])
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        [waiting.send(:settled_changes), Process.clock_gettime(Process::CLOCK_MONOTONIC) - started]
      end
    end

    describe "#step" do
      context "when nothing changed" do
        before do
          allow(poller).to receive(:changes).and_return([])
          allow(session).to receive(:run_tests)
          session.send(:step)
        end

        it "runs nothing" do
          expect(session).not_to have_received(:run_tests)
        end

        it "says nothing" do
          expect(stdout.string).to be_empty
        end
      end

      context "when no recorded test touches the change" do
        before do
          allow(poller).to receive(:changes).and_return(["#{Dir.pwd}/lib/a.rb"], [])
          allow(session).to receive(:run_tests)
          allow(SimpleCov::CLI::Watch::TestPlan).to receive(:build).and_return(run: false, tests: [])
          session.send(:step)
        end

        it "runs nothing" do
          expect(session).not_to have_received(:run_tests)
        end

        it "says so" do
          expect(stdout.string).to eq("lib/a.rb changed, no recorded test touches it\n")
        end
      end

      context "when a recorded test touches the change" do
        let(:live) { session.instance_variable_get(:@live) }

        before do
          allow(live).to receive(:broadcast)
          allow(poller).to receive(:changes).and_return(["#{Dir.pwd}/lib/a.rb"], [])
          allow(SimpleCov::CLI::Watch::TestPlan).to receive(:build).and_return(run: true, tests: %w[spec/a_spec.rb])
          allow(session).to receive(:run_tests)
          session.instance_variable_set(:@document, {"total" => {"lines" => {"percent" => 90.0}}})
          allow(session).to receive(:refresh) do
            session.instance_variable_set(:@document, {"total" => {"lines" => {"percent" => 95.0}}})
          end
          session.send(:step)
        end

        it "reruns the selected tests" do
          expect(session).to have_received(:run_tests).with(%w[spec/a_spec.rb])
        end

        it "reloads the open tabs" do
          expect(live).to have_received(:broadcast)
        end

        it "reports the delta" do
          expect(stdout.string).to eq("lib/a.rb changed, running 1 file... 95.00% (+5.00%)\n")
        end
      end

      context "when a run leaves the report unreadable" do
        let(:live) { session.instance_variable_get(:@live) }

        before do
          allow(live).to receive(:broadcast)
          allow(poller).to receive(:changes).and_return(["#{Dir.pwd}/lib/a.rb"], [])
          allow(SimpleCov::CLI::Watch::TestPlan).to receive(:build).and_return(run: true, tests: nil)
          allow(session).to receive_messages(run_tests: nil, refresh: false)
          session.send(:step)
        end

        it "reloads no tab" do
          expect(live).not_to have_received(:broadcast)
        end

        it "says the report did not regenerate" do
          expect(stdout.string).to eq("lib/a.rb changed, running the full suite... " \
                                      "the report did not regenerate\n")
        end
      end
    end

    describe "#run" do
      let(:server) { instance_double(TCPServer, addr: ["AF_INET", 4321, "localhost", "127.0.0.1"]) }

      before do
        allow(session).to receive_messages(accept_loop: nil, run_tests: nil)
        allow(session).to receive(:poll_forever).and_raise(Interrupt)
        allow(poller).to receive_messages(watch: nil, size: 3)
      end

      context "with a report already there" do
        let(:status) do
          File.write(File.join(tmp, "coverage.json"), JSON.dump("coverage" => {}))
          session.run(server)
        end

        it "answers 0 when interrupted" do
          expect(status).to eq(0)
        end

        it "serves on the listener it was given" do
          status

          expect(session).to have_received(:accept_loop).with(server)
        end

        it "runs nothing first" do
          status

          expect(session).not_to have_received(:run_tests)
        end

        it "announces the session it is serving" do
          status

          expect(stdout.string).to eq("watching 3 files, serving http://127.0.0.1:4321/\n" \
                                      "Press Ctrl-C to stop.\n\nsimplecov watch: stopping\n")
        end
      end

      context "with no report there yet" do
        it "answers a failing status" do
          expect(session.run(server)).to eq(1)
        end

        it "runs the command once" do
          session.run(server)

          expect(session).to have_received(:run_tests).with(nil)
        end

        it "announces nothing" do
          session.run(server)

          expect(stdout.string).to be_empty
        end

        it "reports under its own name" do
          session.run(server)

          expect(stderr.string).to start_with("simplecov watch: ")
        end
      end
    end

    describe "#refresh" do
      context "with a regenerated report" do
        let(:document) { {"coverage" => {"/x/a.rb" => {"lines" => [1]}}, "contexts" => ["spec/a_spec.rb:1"]} }
        let(:refreshed) do
          allow(poller).to receive(:watch)
          session.instance_variable_set(:@root, File.expand_path("/proj"))
          File.write(File.join(tmp, "coverage.json"), JSON.dump(document))
          session.send(:refresh)
        end

        it "answers it" do
          expect(refreshed).to eq(document)
        end

        it "adopts it" do
          refreshed

          expect(session.instance_variable_get(:@document)).to eq(document)
        end

        it "watches every path it names" do
          refreshed

          expect(poller).to have_received(:watch).with(["/x/a.rb", File.expand_path("/proj/spec/a_spec.rb")])
        end
      end

      it "answers false for a report it cannot read" do
        File.write(File.join(tmp, "coverage.json"), "{")

        expect(session.send(:refresh)).to be(false)
      end

      it "reports it under the watch command's own name" do
        File.write(File.join(tmp, "coverage.json"), "{")
        session.send(:refresh)

        expect(stderr.string).to start_with("simplecov watch: ")
      end
    end

    describe "#accept_loop" do
      it "keeps accepting connections after the first, out of the report directory" do
        expect(accepted_bodies)
          .to match([a_string_including("<html>report</html>").and(a_string_including("EventSource('/events')")),
            "static"])
      end

      def accepted_bodies
        File.write(File.join(tmp, "index.html"), "<html>report</html>")
        File.write(File.join(tmp, "extra.txt"), "static")
        server = TCPServer.new("127.0.0.1", 0)
        session.send(:accept_loop, server)
        ["/", "/extra.txt"].collect do |path|
          Net::HTTP.start("127.0.0.1", server.addr[1], open_timeout: 5, read_timeout: 5) do |http|
            http.get(path).body
          end
        end
      ensure
        server&.close
      end
    end

    describe "#run_tests" do
      before { allow(Kernel).to receive(:system) }

      it "runs the named tests with a day-long merge window" do
        session.send(:run_tests, %w[spec/a_spec.rb])

        expect(Kernel).to have_received(:system)
          .with({"SIMPLECOV_MERGE_TIMEOUT" => "86400"}, "true", "spec/a_spec.rb")
      end

      it "runs the command alone when no tests are named" do
        session.send(:run_tests, nil)

        expect(Kernel).to have_received(:system).with({"SIMPLECOV_MERGE_TIMEOUT" => "86400"}, "true")
      end
    end

    describe "#plan_for" do
      context "when it asks for a plan" do
        let(:plan) do
          allow(SimpleCov::CLI::Watch::TestPlan).to receive(:build).and_return(run: true, tests: nil)
          session.instance_variable_set(:@root, "/proj")
          session.instance_variable_set(:@document, {"contexts" => []})
          session.send(:plan_for, ["/proj/lib/a.rb", "/elsewhere/b.rb"])
        end

        it "answers the plan it was handed" do
          expect(plan).to eq(run: true, tests: nil)
        end

        it "asks in paths relative to the project root" do
          plan

          expect(SimpleCov::CLI::Watch::TestPlan).to have_received(:build).with(
            ["lib/a.rb", "/elsewhere/b.rb"], {"contexts" => []},
            root: "/proj", input: File.join(tmp, "coverage.json"), stderr: stderr
          )
        end
      end
    end

    describe "#poll_forever" do
      it "polls until it is interrupted" do
        expect { stamped_polling }.to raise_error(Interrupt)
      end

      it "waits an interval between steps" do
        stamps = []
        suppress(Interrupt) { stamped_polling(stamps) }

        expect(stamps.last - stamps.first).to be >= 0.05
      end

      def stamped_polling(stamps = [])
        waiting = described_class.new(command: %w[true], dir: tmp, interval: 0.05,
          stdout: stdout, stderr: stderr)
        allow(waiting).to receive(:step) do
          stamps << Process.clock_gettime(Process::CLOCK_MONOTONIC)
          raise Interrupt if stamps.size == 3
        end
        waiting.poll_forever
      end
    end

    describe "#total_percent" do
      it "has no percentage to report before a report has been read" do
        expect(session.send(:total_percent)).to be_nil
      end

      it "follows the report's own primary criterion" do
        session.instance_variable_set(:@document,
          {"meta" => {"primary_coverage" => "branch"},
           "total" => {"lines" => {"percent" => 90.0},
                       "branches" => {"percent" => 75.5}}})

        expect(session.send(:total_percent)).to eq(75.5)
      end

      it "falls back to line coverage for a report that names no criterion" do
        session.instance_variable_set(:@document, {"total" => {"lines" => {"percent" => 88.5}}})

        expect(session.send(:total_percent)).to eq(88.5)
      end

      it "reads a whole-number total as a percentage" do
        session.instance_variable_set(:@document, {"total" => {"lines" => {"percent" => 90}}})

        expect(session.send(:total_percent)).to eq(90.0).and be_a(Float)
      end

      it "reads only a number as a percentage" do
        session.instance_variable_set(:@document, {"total" => {"lines" => {"percent" => "90.0"}}})

        expect(session.send(:total_percent)).to be_nil
      end
    end
  end
end
