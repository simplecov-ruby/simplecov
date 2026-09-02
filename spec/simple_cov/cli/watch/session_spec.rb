# frozen_string_literal: true

require "helper"
require "json"
require "net/http"
require "simplecov/cli"
require "socket"
require "support/cli_context"
require "tmpdir"

RSpec.describe SimpleCov::CLI::Watch::Session, mutant_expression: "SimpleCov::CLI::Watch::Session*" do
  include_context "a CLI"

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
