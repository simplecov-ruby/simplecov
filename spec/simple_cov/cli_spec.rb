# frozen_string_literal: true

require "coverage"
require "helper"
require "net/http"
require "open3"
require "simplecov/cli"
require "simplecov/production"
require "socket"
require "stringio"
require "support/captured_runs"
require "support/cli_context"
require "support/git_fixture"
require "tmpdir"

RSpec.shared_context "with a tests report" do
  let(:tmp) { Dir.mktmpdir("simplecov-cli-tests-spec-") }

  def json_path = File.join(tmp, "coverage.json")

  def result_file = "/abs/project/lib/result.rb"

  def quiet_file = "/abs/project/lib/quiet.rb"

  before { File.write(json_path, JSON.dump(payload)) }

  after { FileUtils.remove_entry(tmp) }
end

RSpec.describe SimpleCov::CLI do
  include_context "a CLI"

  describe "dispatch", mutant_expression: ["SimpleCov::CLI#run", "SimpleCov::CLI#dispatch",
    "SimpleCov::CLI#usage", "SimpleCov::CLI#color_enabled?"] do
    it "exits 0 with no arguments" do
      expect(run).to eq(0)
    end

    it "prints usage with no arguments" do
      run

      expect(stdout.string).to include("Usage:")
    end

    it "exits 0 on `help`" do
      expect(run("help")).to eq(0)
    end

    it "prints usage on `help`" do
      run("help")

      expect(stdout.string).to include("Commands:")
    end

    it "exits 0 on `--help`" do
      expect(run("--help")).to eq(0)
    end

    it "prints usage on `--help`" do
      run("--help")

      expect(stdout.string).to include("Commands:")
    end

    it "exits 0 on `-h`" do
      expect(run("-h")).to eq(0)
    end

    it "prints usage on `-h`" do
      run("-h")

      expect(stdout.string).to include("Commands:")
    end

    it "exits non-zero on an unknown command" do
      expect(run("nope")).to eq(1)
    end

    it "complains about an unknown command" do
      run("nope")

      expect(stderr.string).to include('unknown command "nope"')
    end

    it "shows what the commands are when it does not recognize the one it got" do
      run("nope")

      expect(stderr.string).to include("Commands:")
    end

    it "exits non-zero on the process's own streams when it is handed none" do
      expect(without_stderr { described_class.run(["nope"]) }).to eq(1)
    end

    it "complains on the process's own stderr when it is handed none" do
      expect { described_class.run(["nope"]) }.to output(/unknown command "nope"/).to_stderr
    end

    it "exits 0 on the process's own streams when it is handed none" do
      expect(without_stdout { described_class.run(["help"]) }).to eq(0)
    end

    it "prints usage on the process's own stdout when it is handed none" do
      expect { described_class.run(["help"]) }.to output(/Commands:/).to_stdout
    end

    it "exits 0 when the subcommand asks for its own usage" do
      expect(run("uncovered", "--help")).to eq(0)
    end

    it "prints the subcommand's own usage when the subcommand asks for it" do
      run("uncovered", "--help")

      expect(stdout.string).to include("Usage: simplecov uncovered")
    end

    context "with a subcommand that writes to both streams" do
      let(:handler) do
        Class.new do
          def self.run(_rest, stdout:, stderr:)
            stdout.puts("handled")
            stderr.puts("noted")
            0
          end
        end
      end

      before { stub_const("SimpleCov::CLI::COMMANDS", {"fake" => handler}) }

      it "answers what the subcommand answered" do
        expect(run("fake")).to eq(0)
      end

      it "hands the subcommand the very stdout it was given" do
        run("fake")

        expect(stdout.string).to eq("handled\n")
      end

      it "hands the subcommand the very stderr it was given" do
        run("fake")

        expect(stderr.string).to eq("noted\n")
      end
    end

    it "heads the command list it hands out as usage" do
      expect(described_class.usage).to include("Usage:")
    end

    it "lists the commands in the usage it hands out" do
      expect(described_class.usage).to include("Commands:")
    end

    it "colorizes nothing when --no-color was passed, whatever the stream would allow" do
      allow(SimpleCov::Color).to receive(:enabled?).and_return(true)

      expect(described_class.color_enabled?({no_color: true}, stdout)).to be(false)
    end

    it "defers to Color when --no-color was given as false rather than omitted" do
      allow(SimpleCov::Color).to receive(:enabled?).and_return(true)

      expect(described_class.color_enabled?({no_color: false}, stdout)).to be(true)
    end

    it "defers to Color when --no-color was not passed" do
      allow(SimpleCov::Color).to receive(:enabled?).and_return(true)

      expect(described_class.color_enabled?({}, stdout)).to be(true)
    end

    it "asks Color about the very stream it was given" do
      allow(SimpleCov::Color).to receive(:enabled?).and_return(true)
      described_class.color_enabled?({}, stdout)

      expect(SimpleCov::Color).to have_received(:enabled?).with(stdout)
    end

    it "exits non-zero on an unknown option" do
      expect(run("uncovered", "--bogus")).to eq(1)
    end

    it "reports an unknown option as a one-line error" do
      run("uncovered", "--bogus")

      expect(stderr.string).to eq("simplecov uncovered: invalid option: --bogus (run `simplecov help` for usage)\n")
    end

    it "exits non-zero on a malformed typed argument" do
      expect(run("serve", "--port", "foo")).to eq(1)
    end

    it "reports a malformed typed argument as a one-line error" do
      run("serve", "--port", "foo")

      expect(stderr.string).to eq("simplecov serve: invalid argument: --port foo (run `simplecov help` for usage)\n")
    end
  end

  describe "status subcommand", mutant_expression: "SimpleCov::CLI::Status*" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-status-spec-") }
    let(:json_path) { File.join(tmp, "coverage.json") }
    let(:resultset_path) { File.join(tmp, ".resultset.json") }

    before { allow(described_class).to receive(:default_resultset).and_return(resultset_path) }

    after { FileUtils.rm_rf(tmp) }

    def repo!
      GitFixture.init_repo(tmp)
      2.times do |index|
        system("git", "-C", tmp, "commit", "-q", "--allow-empty", "-m", "c#{index}", exception: true)
      end
    end

    def write_report(commit: nil, contexts: nil, generated: Time.now - 120)
      meta = {"simplecov_version" => "9.9.9", "command_name" => "RSpec", "timestamp" => generated.iso8601(3)}
      meta["commit"] = commit if commit
      document = {"meta" => meta, "total" => {"lines" => {"percent" => 92.5}, "branches" => {"percent" => 88.0}}}
      document["contexts"] = contexts if contexts
      File.write(json_path, JSON.dump(document))
    end

    def run_status(*argv)
      Dir.chdir(tmp) { run("status", "--input", json_path, *argv) }
    end

    def write_stale_fixture
      repo!
      first_commit = Dir.chdir(tmp) { `git rev-parse HEAD~1`.strip }
      write_report(commit: first_commit, contexts: ["spec/a_spec.rb:1", "spec/b_spec.rb:2"])
      File.write(resultset_path, JSON.dump("RSpec" => {"coverage" => {}, "timestamp" => (Time.now - 300).to_i}))
      first_commit
    end

    describe "#age_in_words" do
      {
        89 => "89 seconds", 90 => "2 minutes",
        5399 => "90 minutes", 5400 => "2 hours",
        129_599 => "36 hours", 129_600 => "2 days"
      }.each do |seconds, words|
        it "reads #{seconds} seconds as #{words}" do
          expect(described_class::Status.age_in_words(seconds)).to eq(words)
        end
      end

      it "rounds a fractional count of seconds" do
        expect(described_class::Status.age_in_words(12.4)).to eq("12 seconds")
      end
    end

    describe "#commit_words" do
      it "reports a commit that is not a string as unrecorded" do
        expect(described_class::Status.commit_words(commit: 12_345, behind: nil)).to eq("not recorded")
      end
    end

    describe "#report_lines" do
      let(:facts) do
        {generated_at: nil, age: nil, version: "9.9.9", command_name: "RSpec",
         commit: nil, behind: nil, totals: {}, contexts: nil}
      end

      it "omits the totals line when nothing was measured" do
        expect(described_class::Status.report_lines(facts)).to eq(
          ["by simplecov 9.9.9 running RSpec", "commit not recorded",
            "tests recorded: none (enable track_tests to select and re-run by test)"]
        )
      end

      it "prints the totals line when something was" do
        lines = described_class::Status.report_lines(facts.merge(totals: {"line" => 92.5}))

        expect(lines).to include("line 92.50%")
      end
    end

    context "when the report cannot be read" do
      let(:absent) { File.join(tmp, "absent.json") }

      it "exits non-zero" do
        expect(run("status", "--input", absent)).to eq(1)
      end

      it "names itself in the error" do
        run("status", "--input", absent)

        expect(stderr.string).to start_with("simplecov status:")
      end
    end

    context "with a report older than HEAD" do
      let!(:first_commit) { write_stale_fixture }

      it "succeeds" do
        expect(run_status).to eq(0)
      end

      it "names the report it read" do
        run_status

        expect(stdout.string).to include("report #{json_path}")
      end

      it "reports when it was generated" do
        run_status

        expect(stdout.string).to include("generated")
      end

      it "reports its age" do
        run_status

        expect(stdout.string).to include("(2 minutes ago)")
      end

      it "reports the run that generated it" do
        run_status

        expect(stdout.string).to include("by simplecov 9.9.9 running RSpec")
      end

      it "reports its commit distance" do
        run_status

        expect(stdout.string).to include("commit #{first_commit[0, 7]} (1 commit behind HEAD)")
      end

      it "reports its totals" do
        run_status

        expect(stdout.string).to include("line 92.50%, branch 88.00%")
      end

      it "reports the tests it recorded" do
        run_status

        expect(stdout.string).to include("tests recorded: 2 (track_tests)")
      end

      it "names the resultset beside it" do
        run_status

        expect(stdout.string).to include("resultset #{resultset_path}")
      end

      it "reports the resultset's entries" do
        run_status

        expect(stdout.string).to include("RSpec: 5 minutes ago")
      end
    end

    context "with a report at the current HEAD" do
      let!(:head) do
        repo!
        Dir.chdir(tmp) { `git rev-parse HEAD`.strip }.tap { |commit| write_report(commit: commit) }
      end

      it "succeeds" do
        expect(run_status).to eq(0)
      end

      it "reads it as current" do
        run_status

        expect(stdout.string).to include("commit #{head[0, 7]} (current HEAD)")
      end
    end

    context "with a report that records no commit, and no git around" do
      before { write_report }

      it "succeeds" do
        expect(run_status).to eq(0)
      end

      it "reports no commit" do
        run_status

        expect(stdout.string).to include("commit not recorded")
      end

      it "reports no recorded tests" do
        run_status

        expect(stdout.string).to include("tests recorded: none (enable track_tests")
      end

      it "reports no resultset" do
        run_status

        expect(stdout.string).to include("resultset none")
      end
    end

    context "with a commit outside this repository's history" do
      before do
        repo!
        write_report(commit: "0" * 40)
      end

      it "succeeds" do
        expect(run_status).to eq(0)
      end

      it "marks the commit as foreign" do
        run_status

        expect(stdout.string).to include("(not in this repository's history)")
      end
    end

    context "with a report several commits behind" do
      before do
        repo!
        system("git", "-C", tmp, "-c", "user.email=spec@example.com", "-c", "user.name=spec",
          "commit", "-q", "--allow-empty", "-m", "c2", exception: true)
        write_report(commit: Dir.chdir(tmp) { `git rev-parse HEAD~2`.strip })
      end

      it "succeeds" do
        expect(run_status).to eq(0)
      end

      it "counts the commits behind in the plural" do
        run_status

        expect(stdout.string).to include("(2 commits behind HEAD)")
      end
    end

    context "with a minimal document and malformed resultset entries" do
      before do
        File.write(json_path, JSON.dump({}))
        File.write(resultset_path, JSON.dump("Broken" => "junk", "NoStamp" => {"coverage" => {}}))
      end

      it "succeeds" do
        expect(run_status).to eq(0)
      end

      it "reports no commit" do
        run_status

        expect(stdout.string).to include("commit not recorded")
      end

      it "shrugs at a resultset entry that is not an object" do
        run_status

        expect(stdout.string).to include("Broken: age unknown")
      end

      it "shrugs at a resultset entry with no timestamp" do
        run_status

        expect(stdout.string).to include("NoStamp: age unknown")
      end

      it "says nothing about when the report was generated" do
        run_status

        expect(stdout.string).not_to include("generated")
      end
    end

    context "with an unparseable timestamp and a non-object resultset" do
      before do
        write_report
        document = JSON.parse(File.read(json_path))
        document["meta"]["timestamp"] = "junk"
        File.write(json_path, JSON.dump(document))
        File.write(resultset_path, "[]")
      end

      it "succeeds" do
        expect(run_status).to eq(0)
      end

      it "prints the timestamp it could not parse" do
        run_status

        expect(stdout.string).to include("generated junk\n")
      end

      it "reports no resultset" do
        run_status

        expect(stdout.string).to include("resultset none")
      end
    end

    context "with --json" do
      let(:parsed) { JSON.parse(stdout.string) }

      before do
        repo!
        write_report(commit: Dir.chdir(tmp) { `git rev-parse HEAD`.strip },
          contexts: ["spec/a_spec.rb:1"])
      end

      it "succeeds" do
        expect(run_status("--json")).to eq(0)
      end

      it "emits the commit" do
        run_status("--json")

        expect(parsed["commit"]).to eq(Dir.chdir(tmp) { `git rev-parse HEAD`.strip })
      end

      it "emits the commit distance" do
        run_status("--json")

        expect(parsed["behind"]).to eq(0)
      end

      it "emits the recorded test count" do
        run_status("--json")

        expect(parsed["contexts"]).to eq(1)
      end

      it "emits the totals" do
        run_status("--json")

        expect(parsed["totals"]).to eq("line" => 92.5, "branch" => 88.0)
      end
    end

    context "when the report is missing" do
      it "errors like every reader" do
        expect(run_status).to eq(1)
      end

      it "says the report was not found" do
        run_status

        expect(stderr.string).to include("not found")
      end
    end

    it "documents itself in the usage text" do
      run("help")

      expect(stdout.string).to include("status")
    end

    it "speaks seconds" do
      expect(described_class::Status.age_in_words(45)).to eq("45 seconds")
    end

    it "speaks minutes" do
      expect(described_class::Status.age_in_words(600)).to eq("10 minutes")
    end

    it "speaks hours" do
      expect(described_class::Status.age_in_words(7200)).to eq("2 hours")
    end

    it "speaks days" do
      expect(described_class::Status.age_in_words(200_000)).to eq("2 days")
    end
  end

  describe SimpleCov::CLI::Status::Facts, mutant_expression: "SimpleCov::CLI::Status::Facts*" do
    subject(:facts) { described_class }

    describe "#age_of" do
      before { allow(Process).to receive(:clock_gettime).and_return(500.9) }

      it "answers whole seconds between the wall clock and the stored epoch" do
        expect(facts.send(:age_of, 100)).to be(400)
      end

      it "reads the wall clock" do
        facts.send(:age_of, 100)

        expect(Process).to have_received(:clock_gettime).with(Process::CLOCK_REALTIME)
      end
    end

    describe "#whole_seconds" do
      it "cuts the fraction off" do
        expect(facts.send(:whole_seconds, 400.9)).to be(400)
      end

      it "keeps a whole value whole" do
        expect(facts.send(:whole_seconds, 7.0)).to be(7)
      end

      it "cuts toward zero for a clock that went backwards" do
        expect(facts.send(:whole_seconds, -1.7)).to be(-1)
      end
    end

    describe "#commit_count" do
      it "reads the digits git prints, newline and all" do
        expect(facts.send(:commit_count, "42\n")).to be(42)
      end

      it "reads a leading zero as a digit, not as an octal marker" do
        expect(facts.send(:commit_count, "042\n")).to be(42)
      end
    end

    describe "#parse_time" do
      it "reads an ISO 8601 timestamp" do
        expect(facts.parse_time("2026-08-27T12:00:00.000Z")).to eq(Time.utc(2026, 8, 27, 12))
      end

      it "answers nil for a timestamp that is not a string" do
        expect(facts.parse_time(1_756_300_000)).to be_nil
      end

      it "answers nil for a string that is not a timestamp" do
        expect(facts.parse_time("last tuesday")).to be_nil
      end
    end

    describe "#behind" do
      it "counts the commits between the report's and HEAD" do
        allow(SimpleCov::CLI::Git).to receive(:capture).and_return(["9\n", "", true])
        expect(facts.behind("abc1234")).to eq(9)
      end

      it "asks git for the count between that commit and HEAD" do
        allow(SimpleCov::CLI::Git).to receive(:capture).and_return(["0\n", "", true])

        facts.behind("abc1234")
        expect(SimpleCov::CLI::Git).to have_received(:capture).with("rev-list", "--count", "abc1234..HEAD")
      end

      it "answers nil when git cannot answer" do
        allow(SimpleCov::CLI::Git).to receive(:capture).and_return(["", "bad revision", false])
        expect(facts.behind("abc1234")).to be_nil
      end

      it "answers nil for a commit that is not a string" do
        allow(SimpleCov::CLI::Git).to receive(:capture)

        expect(facts.behind(12_345)).to be_nil
      end

      it "does not ask git about a commit that is not a string" do
        allow(SimpleCov::CLI::Git).to receive(:capture)
        facts.behind(12_345)

        expect(SimpleCov::CLI::Git).not_to have_received(:capture)
      end
    end

    describe "#totals" do
      it "names each criterion and keeps its percent" do
        total = {"lines" => {"percent" => 92.5}, "branches" => {"percent" => 88.0},
                 "methods" => {"percent" => 75.0}}

        expect(facts.totals(total)).to eq("line" => 92.5, "branch" => 88.0, "method" => 75.0)
      end

      it "drops a criterion whose percent is not a number" do
        expect(facts.totals("lines" => {"percent" => "92.5"})).to eq({})
      end

      it "answers nothing for a total that is not an object" do
        expect(facts.totals([1, 2])).to eq({})
      end
    end

    describe "#meta_facts" do
      let(:generated) { Time.now - 12.6 }
      let(:written_meta) do
        {"timestamp" => generated.iso8601(3), "simplecov_version" => "9.9.9",
         "command_name" => "RSpec", "commit" => "abc1234"}
      end

      it "answers empty facts for meta that is not an object" do
        expect(facts.meta_facts("meta" => [])).to eq(
          generated_at: nil, age: nil, version: nil, command_name: nil, commit: nil, behind: nil
        )
      end

      it "reads each fact from the metadata it was written under" do
        allow(SimpleCov::CLI::Git).to receive(:capture).and_return(["4\n", "", true])

        expect(facts.meta_facts("meta" => written_meta)).to eq(
          generated_at: generated.iso8601(3), age: 12, version: "9.9.9",
          command_name: "RSpec", commit: "abc1234", behind: 4
        )
      end
    end

    describe "#gather" do
      let(:gathered_from_three_contexts) do
        {
          generated_at: nil, age: nil, version: nil, command_name: nil, commit: nil, behind: nil,
          totals: {}, contexts: 3,
          resultset_path: "/nonexistent/.resultset.json", resultset: nil
        }
      end

      it "counts the recorded contexts, and says where the resultset was sought" do
        expect(facts.gather({"contexts" => %w[a b c]}, "/nonexistent/.resultset.json"))
          .to eq(gathered_from_three_contexts)
      end

      it "gathers the totals and the resultset together" do
        expect(gathered_beside_a_resultset)
          .to include(totals: {"line" => 92.5}, contexts: nil,
            resultset: [{command: "RSpec", age: 60}])
      end

      def gathered_beside_a_resultset
        Dir.mktmpdir("simplecov-gather-spec-") do |dir|
          path = File.join(dir, ".resultset.json")
          File.write(path, JSON.dump("RSpec" => {"timestamp" => (Time.now - 60).to_i}))
          facts.gather({"total" => {"lines" => {"percent" => 92.5}}}, path)
            .merge(resultset_path: path)
        end
      end

      it "answers no count for a report that recorded no contexts at all" do
        expect(facts.gather({}, "/nonexistent/.resultset.json")[:contexts]).to be_nil
      end

      it "answers no count for contexts that are not a list" do
        answered = facts.gather({"contexts" => "a_spec.rb"}, "/nonexistent/.resultset.json")

        expect(answered[:contexts]).to be_nil
      end
    end

    describe "#readable_resultset" do
      let(:path) { File.join(dir, ".resultset.json") }
      let(:dir) { Dir.mktmpdir("simplecov-facts-spec-") }

      after { FileUtils.remove_entry(dir) }

      it "ages each command against the time it recorded" do
        File.write(path, JSON.dump("RSpec" => {"timestamp" => (Time.now - 300).to_i}))
        expect(facts.readable_resultset(path)).to eq([{command: "RSpec", age: 300}])
      end

      it "answers no age for an entry that carries no timestamp" do
        File.write(path, JSON.dump("RSpec" => {"coverage" => {}}))
        expect(facts.readable_resultset(path)).to eq([{command: "RSpec", age: nil}])
      end

      it "answers no age for a timestamp that is not a number" do
        File.write(path, JSON.dump("RSpec" => {"timestamp" => "recently"}))
        expect(facts.readable_resultset(path)).to eq([{command: "RSpec", age: nil}])
      end

      it "answers no age for an entry that is not an object" do
        File.write(path, JSON.dump("RSpec" => []))
        expect(facts.readable_resultset(path)).to eq([{command: "RSpec", age: nil}])
      end

      it "answers nil when the resultset is not there" do
        expect(facts.readable_resultset(File.join(dir, "absent.json"))).to be_nil
      end

      it "answers nil when the resultset is not JSON" do
        File.write(path, "not json")
        expect(facts.readable_resultset(path)).to be_nil
      end

      it "answers nil when the resultset is not an object" do
        File.write(path, JSON.dump([1, 2]))
        expect(facts.readable_resultset(path)).to be_nil
      end
    end
  end

  describe "badge subcommand", mutant_expression: "SimpleCov::CLI::Badge*" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-badge-spec-") }
    let(:json_path) { File.join(tmp, "coverage.json") }
    let(:reference_badge) do
      <<~SVG
        <svg xmlns="http://www.w3.org/2000/svg" width="153" height="20" role="img" aria-label="line coverage: 92.50%">
          <title>line coverage: 92.50%</title>
          <linearGradient id="s" x2="0" y2="100%">
            <stop offset="0" stop-color="#bbb" stop-opacity=".1"/>
            <stop offset="1" stop-opacity=".1"/>
          </linearGradient>
          <clipPath id="r"><rect width="153" height="20" rx="3" fill="#fff"/></clipPath>
          <g clip-path="url(#r)">
            <rect width="101" height="20" fill="#555"/>
            <rect x="101" width="52" height="20" fill="#4c1"/>
            <rect width="153" height="20" fill="url(#s)"/>
          </g>
          <g fill="#fff" text-anchor="middle" font-family="Verdana,Geneva,DejaVu Sans,sans-serif" text-rendering="geometricPrecision" font-size="110">
            <text aria-hidden="true" x="505" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="910">line coverage</text>
            <text x="505" y="140" transform="scale(.1)" fill="#fff" textLength="910">line coverage</text>
            <text aria-hidden="true" x="1270" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="420">92.50%</text>
            <text x="1270" y="140" transform="scale(.1)" fill="#fff" textLength="420">92.50%</text>
          </g>
        </svg>
      SVG
    end

    after { FileUtils.rm_rf(tmp) }

    def write_report(line: 92.5, branch: nil)
      totals = {"lines" => {"percent" => line}}
      totals["branches"] = {"percent" => branch} if branch
      File.write(json_path, JSON.dump("meta" => {}, "total" => totals))
    end

    def run_badge(*argv)
      run("badge", "--input", json_path, *argv)
    end

    context "with a known percent" do
      before { write_report(line: 92.5) }

      it "succeeds" do
        expect(run_badge).to eq(0)
      end

      it "prints the whole flat SVG badge" do
        run_badge

        expect(stdout.string).to eq(reference_badge)
      end
    end

    describe "geometry" do
      let(:svg) { described_class::Badge::Svg }

      it "sizes an empty segment as the padding alone" do
        expect(svg.width("")).to eq(10)
      end

      it "sizes a segment by its text, with padding on both sides" do
        expect(svg.width("abc")).to eq(31)
      end

      it "places the segments side by side and centers each caption in its own" do
        expect(svg.geometry(101, 52)).to eq(
          label_width: 101, value_width: 52, total: 153,
          label_x: 505, value_x: 1270, label_span: 910, value_span: 420
        )
      end

      it "keeps the value segment centered past the label, not over it" do
        expect(svg.geometry(20, 40)).to include(label_x: 100, value_x: 400, total: 60)
      end

      it "spans the caption over its segment less the padding" do
        expect(svg.geometry(31, 31)).to include(label_span: 210, value_span: 210)
      end
    end

    context "with a criterion below the top rung" do
      before { write_report(line: 92.5, branch: 55.0) }

      it "succeeds" do
        expect(run_badge("--criterion", "branch")).to eq(0)
      end

      it "follows the chosen criterion" do
        run_badge("--criterion", "branch")

        expect(stdout.string).to include('aria-label="branch coverage: 55.00%"')
      end

      it "colors the lower rung" do
        run_badge("--criterion", "branch")

        expect(stdout.string).to include('fill="#fe7d37"')
      end
    end

    it "steps through the whole color ladder" do
      colors = [95, 85, 75, 65, 55, 45].collect { |pct| described_class::Badge::Svg.color(pct) }
      expect(colors).to eq(["#4c1", "#97ca00", "#a4a61d", "#dfb317", "#fe7d37", "#e05d44"])
    end

    it "gives each rung's boundary to the rung it names" do
      colors = [90, 80, 70, 60, 50].collect { |pct| described_class::Badge::Svg.color(pct) }
      expect(colors).to eq(["#4c1", "#97ca00", "#a4a61d", "#dfb317", "#fe7d37"])
    end

    it "succeeds on --help" do
      expect(run("badge", "--help")).to eq(0)
    end

    it "answers its own usage for --help" do
      run("badge", "--help")

      expect(stdout.string).to include("badge options:")
    end

    it "lists its own options in that usage" do
      run("badge", "--help")

      expect(stdout.string).to include("--criterion")
    end

    it "wires the shared help handler rather than leaving optparse's" do
      expect(raised_by_badge_help).to be_a(SimpleCov::CLI::CommandHelpers::HelpRequested)
    end

    def raised_by_badge_help
      described_class::Badge.parse(["--help"])
      nil
    rescue Exception => e # rubocop:disable Lint/RescueException
      e
    end

    context "with no input path" do
      around do |example|
        previous = described_class.instance_variable_get(:@coverage_dir)
        described_class.instance_variable_set(:@coverage_dir, nil)
        Dir.mktmpdir("simplecov-cli-badge-default-") do |dir|
          FileUtils.mkdir_p(File.join(dir, "coverage"))
          File.write(File.join(dir, "coverage", "coverage.json"),
            JSON.dump("meta" => {}, "total" => {"lines" => {"percent" => 92.5}}))
          Dir.chdir(dir) { example.run }
        end
      ensure
        described_class.instance_variable_set(:@coverage_dir, previous)
      end

      it "succeeds" do
        expect(run("badge")).to eq(0)
      end

      it "reads the default report" do
        run("badge")

        expect(stdout.string).to include('aria-label="line coverage: 92.50%"')
      end
    end

    context "with --output" do
      let(:target) { File.join(tmp, "badge.svg") }

      before { write_report }

      it "succeeds" do
        expect(run_badge("--output", target)).to eq(0)
      end

      it "writes the badge to the file" do
        run_badge("--output", target)

        expect(File.read(target)).to include(">92.50%</text>")
      end

      it "stays quiet" do
        run_badge("--output", target)

        expect(stdout.string).to be_empty
      end
    end

    context "with --label" do
      before { write_report }

      it "succeeds" do
        expect(run_badge("--label", "lines <&> \"covered\"")).to eq(0)
      end

      it "renames the label and escapes markup in it" do
        run_badge("--label", "lines <&> \"covered\"")

        expect(stdout.string).to include(">lines &lt;&amp;&gt; &quot;covered&quot;</text>")
      end
    end

    context "with an unknown criterion" do
      before { write_report }

      it "errors" do
        expect(run_badge("--criterion", "files")).to eq(1)
      end

      it "names the criteria it knows" do
        run_badge("--criterion", "files")

        expect(stderr.string)
          .to eq("simplecov badge: unknown --criterion :files (expected line, branch, or method)\n")
      end
    end

    context "when the report carries no totals at all" do
      before { File.write(json_path, JSON.dump("meta" => {})) }

      it "errors" do
        expect(run_badge).to eq(1)
      end

      it "says which totals it wanted" do
        run_badge

        expect(stderr.string).to include("no line totals in #{json_path}")
      end
    end

    context "when the report has no totals for the criterion" do
      before { write_report(line: 92.5) }

      it "errors" do
        expect(run_badge("--criterion", "branch")).to eq(1)
      end

      it "says which totals it wanted" do
        run_badge("--criterion", "branch")

        expect(stderr.string).to include("no branch totals in #{json_path}")
      end
    end

    context "when the report is missing" do
      it "errors" do
        expect(run_badge).to eq(1)
      end

      it "says so under its own command name" do
        run_badge

        expect(stderr.string).to eq("simplecov badge: #{json_path} not found\n")
      end
    end

    context "when the recorded percent is not a number" do
      before { File.write(json_path, JSON.dump("meta" => {}, "total" => {"lines" => {"percent" => "92.5"}})) }

      it "errors" do
        expect(run_badge).to eq(1)
      end

      it "says which totals it wanted" do
        run_badge

        expect(stderr.string).to include("no line totals in #{json_path}")
      end
    end

    context "when the totals section is not an object at all" do
      before { File.write(json_path, JSON.dump("meta" => {}, "total" => "junk")) }

      it "errors" do
        expect(run_badge).to eq(1)
      end

      it "says which totals it wanted" do
        run_badge

        expect(stderr.string).to include("no line totals in #{json_path}")
      end
    end

    context "with a totals section that arrives as a Hash subclass" do
      before do
        totals = Class.new(Hash).new.merge!("lines" => {"percent" => 92.5})
        allow(SimpleCov::CLI::CoverageFile).to receive(:load_document).and_return({"total" => totals})
      end

      it "succeeds" do
        expect(run_badge).to eq(0)
      end

      it "reads the totals out of it" do
        run_badge

        expect(stdout.string).to include('aria-label="line coverage: 92.50%"')
      end
    end

    it "passes xmllint's validation" do
      skip "xmllint is not installed here" unless system("xmllint", "--version", out: File::NULL, err: File::NULL)

      expect(system("xmllint", "--noout", written_badge)).to be(true)
    end

    def written_badge
      write_report
      run_badge
      File.join(tmp, "badge.svg").tap { |file| File.write(file, stdout.string) }
    end
  end

  describe "completions subcommand", mutant_expression: "SimpleCov::CLI::Completions*" do
    def shell_available?(shell)
      system(shell, "-c", "true", out: File::NULL, err: File::NULL)
    end

    def generate(shell)
      run("completions", shell)
      stdout.string
    end

    it "errors without a shell" do
      expect(run("completions")).to eq(1)
    end

    it "says which shells it knows when given none" do
      run("completions")

      expect(stderr.string).to eq("simplecov completions: missing shell (expected fish, bash, or zsh)\n")
    end

    it "errors on an unknown shell" do
      expect(run("completions", "tcsh")).to eq(1)
    end

    it "says which shells it knows when given one it does not" do
      run("completions", "tcsh")

      expect(stderr.string).to eq("simplecov completions: unknown shell \"tcsh\" (expected fish, bash, or zsh)\n")
    end

    it "succeeds on --help" do
      expect(run("completions", "--help")).to eq(0)
    end

    it "answers its own usage for --help" do
      run("completions", "--help")

      expect(stdout.string).to include("completions <shell>")
    end

    describe "the generated fish script" do
      subject(:script) { generate("fish") }

      it "succeeds" do
        expect(run("completions", "fish")).to eq(0)
      end

      it "completes each subcommand" do
        expect(script).to include("complete -c simplecov -f -n __fish_use_subcommand -a affected")
      end

      it "guards a subcommand's own options behind it" do
        expect(script).to include("__fish_seen_subcommand_from affected")
      end

      it "marks an option that takes an argument" do
        expect(script).to include("-l base -r")
      end

      it "carries an option's short form beside its long one" do
        expect(script).to include("-s q -l quiet")
      end

      it "completes a subcommand's positional argument" do
        expect(script).to include("-a 'fish bash zsh'")
      end

      it "offers every subcommand its own --help" do
        expect(script).to include("-l help")
      end
    end

    describe "the generated bash script" do
      subject(:script) { generate("bash") }

      it "succeeds" do
        expect(run("completions", "bash")).to eq(0)
      end

      it "declares the completion function" do
        expect(script).to include("_simplecov()")
      end

      it "registers it" do
        expect(script).to include("complete -o default -F _simplecov simplecov")
      end

      it "lists a subcommand's own options" do
        expect(script).to match(/affected\)\s+opts="[^"]*--base/)
      end

      it "completes a subcommand's positional argument" do
        expect(script).to include('compgen -W "fish bash zsh -h --help"')
      end
    end

    describe "the generated zsh script" do
      subject(:script) { generate("zsh") }

      it "succeeds" do
        expect(run("completions", "zsh")).to eq(0)
      end

      it "opens with the compdef line" do
        expect(script).to include("#compdef simplecov")
      end

      it "describes the subcommands" do
        expect(script).to include("_describe")
      end

      it "marks an option that takes an argument" do
        expect(script).to include("'--base=[")
      end

      it "completes a subcommand's positional argument" do
        expect(script).to include("'1:shell:(fish bash zsh)'")
      end
    end

    describe "the rendered scripts" do
      let(:completions_name) { +"completions" }
      let(:commands) { [["report", "Print the summary"], [completions_name, "Emit the script"]] }
      let(:options) do
        {completions_name => [{short: nil, long: "--input", arg: "PATH", desc: "Read from PATH"}],
         "report" => [{short: nil, long: "--json", arg: nil, desc: "Emit JSON"},
           {short: "-q", long: "--quiet", arg: nil, desc: "Say nothing"}]}
      end

      def scripts = described_class::Completions::Scripts

      def fish_script
        <<~FISH.chomp
          # Completions for simplecov. Generated by `simplecov completions fish`.
          complete -c simplecov -f -n __fish_use_subcommand -a report -d 'Print the summary'
          complete -c simplecov -f -n __fish_use_subcommand -a completions -d 'Emit the script'
          complete -c simplecov -n '__fish_seen_subcommand_from completions' -l input -r -d 'Read from PATH'
          complete -c simplecov -n '__fish_seen_subcommand_from report' -l json -d 'Emit JSON'
          complete -c simplecov -n '__fish_seen_subcommand_from report' -s q -l quiet -d 'Say nothing'
          complete -c simplecov -f -n '__fish_seen_subcommand_from completions' -a 'fish bash zsh'
        FISH
      end

      def bash_script
        <<~BASH.chomp
          # Completions for simplecov. Generated by `simplecov completions bash`.
          _simplecov() {
            local cur="${COMP_WORDS[COMP_CWORD]}" opts=""
            if [ "$COMP_CWORD" -eq 1 ]; then
              COMPREPLY=( $(compgen -W "report completions" -- "$cur") ); return
            fi
            case "${COMP_WORDS[1]}" in
              completions) COMPREPLY=( $(compgen -W "fish bash zsh -h --help" -- "$cur") ); return;;
              report) opts="--json -q --quiet";;
            esac
            [[ "$cur" == -* ]] && COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
          }
          complete -o default -F _simplecov simplecov
        BASH
      end

      def zsh_script
        <<~ZSH.chomp
          #compdef simplecov
          # Completions for simplecov. Generated by `simplecov completions zsh`.
          _simplecov() {
            local -a commands
            commands=(
              'report:Print the summary'
              'completions:Emit the script'
            )
            if (( CURRENT == 2 )); then
              _describe -t commands 'simplecov command' commands
              return
            fi
            case "$words[2]" in
              completions) _arguments '1:shell:(fish bash zsh)' '--input=[Read from PATH]';;
              report) _arguments '--json[Emit JSON]' '-q[Say nothing]' '--quiet[Say nothing]';;
            esac
          }
          _simplecov "$@"
        ZSH
      end

      it "renders the whole fish script" do
        expect(scripts.fish(commands, options)).to eq(fish_script)
      end

      it "renders the whole bash script" do
        expect(scripts.bash(commands, options)).to eq(bash_script)
      end

      it "renders the whole zsh script" do
        expect(scripts.zsh(commands, options)).to eq(zsh_script)
      end

      it "escapes quotes in a zsh command description" do
        expect(quoting_zsh_script).to include("'show:Print the file'\\''s source'")
      end

      it "escapes quotes in a zsh option description" do
        expect(quoting_zsh_script).to include("'--json[Emit the file'\\''s JSON]'")
      end

      def quoting_zsh_script
        scripts.zsh(
          [["show", "Print the file's source"]],
          {"show" => [{short: nil, long: "--json", arg: nil, desc: "Emit the file's JSON"}]}
        )
      end

      it "escapes every backslash for fish, not just the first" do
        expect(scripts.fish_quote(%q(a \ b \ c))).to eq("'a \\\\ b \\\\ c'")
      end

      it "escapes every quote for fish, not just the first" do
        expect(scripts.fish_quote("it's o'clock")).to eq(%q('it\'s o\'clock'))
      end

      it "escapes quotes for zsh by closing, quoting, and reopening" do
        expect(scripts.zsh_quote("it's here")).to eq("it'\\''s here")
      end

      it "drops brackets from a zsh description" do
        expect(scripts.zsh_specs(short: nil, long: "--x", arg: nil, desc: "a [bracketed] note"))
          .to eq(["'--x[a bracketed note]'"])
      end
    end

    describe "the parsed usage" do
      let(:completions) { described_class::Completions }

      it "reads each command row as its name and its description" do
        expect(completions.commands.first).to eq(["run", "Execute <command> with SimpleCov pre-loaded"])
      end

      it "reads every command out of the table" do
        expect(completions.commands.collect(&:first)).to include("badge", "completions", "help")
      end

      it "keeps the table's own header and wrapped continuations out of the commands" do
        expect(completions.commands.collect(&:first)).not_to include("Commands:", "(works")
      end

      it "gives a command the options of its own sections" do
        expect(badge_longs).to include("--output", "--criterion", "--label")
      end

      it "gives it no others" do
        expect(badge_longs).not_to include("--threshold", "--fail-on-drop")
      end

      def badge_longs
        completions.options_for("badge").collect { |option| option[:long] }
      end

      it "reads a switch's short form and description together" do
        expect(completions.options_for("merge").detect { |option| option[:long] == "--quiet" })
          .to eq(short: "-q", long: "--quiet", arg: nil, desc: "Suppress the success status line")
      end

      it "reads a switch's argument" do
        expect(completions.options_for("badge").detect { |option| option[:long] == "--output" })
          .to include(short: nil, arg: "PATH")
      end

      it "offers every command its own --help, with the short form too" do
        expect(completions.options_for("badge").last)
          .to eq(short: "-h", long: "--help", arg: nil, desc: "Show this command's usage")
      end

      it "leaves run without options" do
        expect(completions.options_for("run")).to eq([])
      end

      it "leaves run out of the option table" do
        expect(completions.options_by_command).not_to have_key("run")
      end

      it "keys the option table by command" do
        expect(completions.options_by_command).to be_a(Hash)
      end

      it "folds a wrapped description onto the option it belongs to, not the first one" do
        expect(completions.section_options(wrapped_section)).to eq(
          [{short: nil, long: "--dry-run", arg: nil, desc: "Print what would be removed"},
            {short: "-q", long: "--quiet", arg: nil, desc: "Suppress status lines entirely"}]
        )
      end

      def wrapped_section
        ["clean options:",
          "  --dry-run                 Print what would",
          "                            be removed",
          "  -q, --quiet               Suppress status",
          "                            lines entirely", ""].join("\n")
      end
    end

    context "with a stray line before the first option" do
      let(:options) do
        section = ["clean options:",
          "  a stray note",
          "  --dry-run                 Print what would",
          "                            be removed", ""].join("\n")
        described_class::Completions.section_options(section)
      end

      it "ignores the stray line" do
        expect(options.collect { |option| option[:long] }).to eq(["--dry-run"])
      end

      it "folds the wrapped description into its own option" do
        expect(options.first[:desc]).to eq("Print what would be removed")
      end
    end

    it "leaves run's arguments to the command being run" do
      expect(generate("fish")).not_to include("__fish_seen_subcommand_from run'")
    end

    %w[fish bash zsh].each do |shell|
      it "passes #{shell}'s own syntax check" do
        skip "#{shell} is not installed here" unless shell_available?(shell)

        script = File.join(Dir.mktmpdir("simplecov-completions-"), "script")
        File.write(script, generate(shell))
        expect(system(shell, "-n", script)).to be(true)
      end
    end
  end

  describe "per-command help", mutant_expression: "SimpleCov::CLI::Usage*" do
    let(:clean_help) do
      <<~HELP
        Usage: simplecov clean [options]

        clean                     Remove the coverage report directory

        clean options:
          --dry-run                 Print what would be removed without deleting
          -q, --quiet               Suppress status lines
      HELP
    end

    describe ".heading_of" do
      it "reads the first line, shorn of the whitespace around both ends" do
        expect(SimpleCov::CLI::Usage.send(:heading_of, "  merge options:  \n  --quiet\n"))
          .to eq("merge options:")
      end

      it "answers an empty heading for an empty section" do
        expect(SimpleCov::CLI::Usage.send(:heading_of, "")).to eq("")
      end
    end

    %w[coverage show report uncovered tests affected merge diff patch open serve watch clean status
      completions badge].each do |command|
      it "succeeds on `#{command} --help`" do
        expect(run(command, "--help")).to eq(0)
      end

      it "answers `#{command} --help` with that command's usage" do
        run(command, "--help")

        expect(stdout.string).to include("Usage: simplecov #{command} [options]")
      end

      it "says nothing on stderr for `#{command} --help`" do
        run(command, "--help")

        expect(stderr.string).to be_empty
      end
    end

    context "with a command's own -h" do
      before { run("affected", "-h") }

      it "heads the command's own options" do
        expect(stdout.string).to include("affected options:")
      end

      it "shows an option of the command's own" do
        expect(stdout.string).to include("--base REF")
      end

      it "shows a shared option the command takes" do
        expect(stdout.string).to include("--input PATH")
      end

      it "leaves another command's options out" do
        expect(stdout.string).not_to include("merge options:")
      end
    end

    it "succeeds on -h" do
      expect(run("affected", "-h")).to eq(0)
    end

    it "names the command in the header row" do
      run("watch", "--help")

      expect(stdout.string).to include("Re-run <command> on save")
    end

    it "degrades to a bare usage line for a name with no listing" do
      expect(described_class::Usage.for(described_class, "bogus")).to eq("Usage: simplecov bogus [options]")
    end

    it "answers with the usage line, the row and the options, spaced apart" do
      expect(described_class::Usage.for(described_class, "clean")).to eq(clean_help)
    end

    it "reads a command name as a name and not as a pattern" do
      expect(described_class::Usage.for(described_class, "cle.n")).to eq("Usage: simplecov cle.n [options]")
    end

    it "takes no section out of an empty usage" do
      expect(described_class::Usage.section_for?("", "clean")).to be(false)
    end

    it "takes no section for a command no heading names" do
      expect(described_class::Usage.section_for?("Commands:\n  clean\n", "clean")).to be(false)
    end

    it "takes no section from a heading that names the command but lists no options" do
      expect(described_class::Usage.section_for?("clean and friends:\n  --dry-run\n", "clean")).to be(false)
    end

    it "takes no section for a name that is only part of one it lists" do
      expect(described_class::Usage.section_for?("clean options:\n", "lea")).to be(false)
    end

    it "takes no section for the word that marks the heading" do
      expect(described_class::Usage.section_for?("options:\n", "options:")).to be(false)
    end

    it "takes no section for no name at all" do
      expect(described_class::Usage.section_for?("show  coverage options:\n", "")).to be(false)
    end

    it "takes a section whose heading lists the command among others" do
      expect(described_class::Usage.section_for?("show/coverage options:\n  --input PATH\n", "coverage")).to be(true)
    end

    describe "the paths the usage names" do
      let(:lines) { described_class::Usage.text(described_class).lines }
      let(:inputs) { lines.grep(/Read from PATH instead of/).grep_v(/\.history\.json/) }

      it "names the default input for every command that reads one" do
        expect(inputs.size).to eq(2)
      end

      it "names this run's default input" do
        expect(inputs).to all(end_with("instead of #{described_class.default_input}\n"))
      end

      it "names this run's default resultset" do
        expect(lines.grep(/Write merged resultset/))
          .to all(end_with("(default: #{described_class.default_resultset})\n"))
      end

      it "names this run's default report" do
        expect(lines.grep(/Open PATH instead of/))
          .to all(end_with("instead of #{described_class.default_report}\n"))
      end

      it "names this run's coverage directory" do
        expect(lines.grep(/SimpleCov\.coverage_dir/))
          .to all(include("(#{described_class.coverage_dir} for this run)"))
      end
    end
  end

  describe ".coverage_dir", mutant_expression: ["SimpleCov::CLI#coverage_dir", "SimpleCov::CLI#default_input",
    "SimpleCov::CLI#default_report", "SimpleCov::CLI#default_resultset",
    "SimpleCov::CLI::Dotfile*"] do
    around do |example|
      previous = described_class.instance_variable_get(:@coverage_dir)
      described_class.instance_variable_set(:@coverage_dir, nil)
      example.run
    ensure
      described_class.instance_variable_set(:@coverage_dir, previous)
    end

    it "looks for the coverage JSON under the coverage directory" do
      allow(described_class).to receive(:coverage_dir).and_return("my/reports")

      expect(described_class.default_input).to eq("my/reports/coverage.json")
    end

    it "looks for the HTML report's index under the coverage directory" do
      allow(described_class).to receive(:coverage_dir).and_return("my/reports")

      expect(described_class.default_report).to eq("my/reports/index.html")
    end

    it "looks for the resultset under the coverage directory" do
      allow(described_class).to receive(:coverage_dir).and_return("my/reports")

      expect(described_class.default_resultset).to eq("my/reports/.resultset.json")
    end

    it "loads simplecov itself when a standalone process asks for the dotfile" do
      allow(SimpleCov::CLI::Dotfile).to receive(:require)

      SimpleCov::CLI::Dotfile.send(:load_simplecov)

      expect(SimpleCov::CLI::Dotfile).to have_received(:require).with("simplecov")
    end

    it "honors SimpleCov.coverage_dir from a project .simplecov" do
      expect(coverage_dir_under(%(SimpleCov.coverage_dir "my/reports"\n))).to eq("my/reports")
    end

    it "falls back to 'coverage' when no .simplecov is found" do
      expect(coverage_dir_under(nil)).to eq("coverage")
    end

    # Answers CLI.coverage_dir as read in a scratch directory holding the given
    # .simplecov, or none at all when it is nil.
    def coverage_dir_under(dotfile)
      Dir.mktmpdir do |tmp|
        File.write(File.join(tmp, ".simplecov"), dotfile) if dotfile
        Dir.chdir(tmp) { described_class.coverage_dir }
      end
    end

    context "when the dotfile calls SimpleCov.start" do
      around do |example|
        Dir.mktmpdir do |tmp|
          File.write(File.join(tmp, ".simplecov"), <<~RUBY)
            SimpleCov.start do
              coverage_dir "from/start_block"
            end
          RUBY
          Dir.chdir(tmp) { example.run }
        end
      end

      it "reads the coverage_dir out of the start block" do
        expect(described_class.coverage_dir).to eq("from/start_block")
      end

      it "does not start coverage tracking" do
        was_running = Coverage.running?
        described_class.coverage_dir

        expect(Coverage.running?).to eq(was_running)
      end
    end

    context "with a dotfile that raises" do
      let(:dotfile) { "raise 'boom'\n" }

      it "falls back to 'coverage'" do
        expect(without_stderr { coverage_dir_under(dotfile) }).to eq("coverage")
      end

      it "warns, naming the error it caught" do
        expect { coverage_dir_under(dotfile) }
          .to output(/simplecov: failed to read coverage_dir.*RuntimeError.*boom/).to_stderr
      end
    end

    context "with a dotfile that does not parse" do
      let(:dotfile) { "SimpleCov.start do\n" }

      it "falls back to 'coverage'" do
        expect(without_stderr { coverage_dir_under(dotfile) }).to eq("coverage")
      end

      it "warns, naming the error it caught" do
        expect { coverage_dir_under(dotfile) }
          .to output(/simplecov: failed to read coverage_dir.*SyntaxError/).to_stderr
      end
    end

    context "with a dotfile that raises mid-config" do
      let(:dotfile) { %(SimpleCov.coverage_dir "clobbered"\nraise "boom"\n) }

      it "warns" do
        expect { coverage_dir_under(dotfile) }.to output(/failed to read coverage_dir/).to_stderr
      end

      it "restores a host process's configured coverage_dir" do
        configured = SimpleCov.instance_variable_get(:@coverage_dir)
        without_stderr { coverage_dir_under(dotfile) }

        expect(SimpleCov.instance_variable_get(:@coverage_dir)).to eq(configured)
      end
    end
  end

  describe "coverage JSON input errors",
    mutant_expression: ["SimpleCov::CLI::CoverageFile*", "SimpleCov::CLI::CommandHelpers*",
      "SimpleCov::CoverageJSON*"] do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-json-errors-spec-") }
    let(:invalid) { File.join(tmp, "invalid.json") }
    let(:valid) { File.join(tmp, "valid.json") }

    before do
      File.write(invalid, "{")
      File.write(valid, JSON.dump("coverage" => {}))
    end

    after { FileUtils.remove_entry(tmp) }

    [
      ["coverage", ->(bad, _good) { ["coverage", "--input", bad, "lib/a.rb"] }],
      ["report", ->(bad, _good) { ["report", "--input", bad] }],
      ["uncovered", ->(bad, _good) { ["uncovered", "--input", bad] }],
      ["diff baseline", ->(bad, good) { ["diff", "--input", good, bad] }],
      ["diff current", ->(bad, good) { ["diff", "--input", bad, good] }],
      ["tests", ->(bad, _good) { ["tests", "--input", bad] }],
      ["affected", ->(bad, _good) { ["affected", "--input", bad] }],
      ["show", ->(bad, _good) { ["show", "--input", bad, "lib/a.rb"] }],
      ["ratchet", ->(bad, _good) { ["ratchet", "--input", bad, "--dry-run"] }],
      ["dead-code", ->(bad, good) { ["dead-code", "--input", bad, "--production", good] }]
    ].each do |description, argv_for|
      context "with malformed JSON for #{description}" do
        let(:argv) { argv_for.call(invalid, valid) }

        it "errors" do
          expect(run(*argv)).to eq(1)
        end

        it "says nothing on stdout" do
          run(*argv)

          expect(stdout.string).to be_empty
        end

        it "names the subcommand" do
          run(*argv)

          expect(stderr.string).to start_with("simplecov #{argv.first}:")
        end

        it "names the file" do
          run(*argv)

          expect(stderr.string).to include(invalid)
        end

        it "says what was wrong with it" do
          run(*argv)

          expect(stderr.string).to include("isn't valid JSON")
        end

        it "says it in one line" do
          run(*argv)

          expect(stderr.string.lines.size).to eq(1)
        end

        it "keeps the parser's own error class out of it" do
          run(*argv)

          expect(stderr.string).not_to include("JSON::ParserError")
        end
      end
    end

    ["null", "[]"].each do |document|
      context "with the #{document} top-level JSON value" do
        before { File.write(invalid, document) }

        it "errors" do
          expect(run("report", "--input", invalid)).to eq(1)
        end

        it "says what the top-level value should have been" do
          run("report", "--input", invalid)

          expect(stderr.string).to include("top-level value must be an object")
        end
      end
    end

    context "with invalid UTF-8 in the source" do
      before { File.binwrite(invalid, "{\"coverage\":{\"lib/a.rb\":{\"source\":[\"\xFF\"]}}}".b) }

      def run_coverage_json
        run("coverage", "--input", invalid, "--json", "lib/a.rb")
      end

      it "errors before generating JSON output" do
        expect(run_coverage_json).to eq(1)
      end

      it "says nothing on stdout" do
        run_coverage_json

        expect(stdout.string).to be_empty
      end

      it "names the subcommand" do
        run_coverage_json

        expect(stderr.string).to include("simplecov coverage:")
      end

      it "says what was wrong with it" do
        run_coverage_json

        expect(stderr.string).to include("not valid UTF-8")
      end

      it "says it in one line" do
        run_coverage_json

        expect(stderr.string.lines.size).to eq(1)
      end

      it "keeps the generator's own error class out of it" do
        run_coverage_json

        expect(stderr.string).not_to include("JSON::GeneratorError")
      end
    end

    context "with a non-object coverage field" do
      before { File.write(invalid, JSON.dump("coverage" => [])) }

      it "errors" do
        expect(run("uncovered", "--input", invalid)).to eq(1)
      end

      it "says what the field should have been" do
        run("uncovered", "--input", invalid)

        expect(stderr.string).to eq(
          %(simplecov uncovered: input file #{invalid.inspect} isn't valid JSON ("coverage" must be an object)\n)
        )
      end
    end

    context "with an input path that cannot be read as a file" do
      it "errors" do
        expect(run("report", "--input", tmp)).to eq(1)
      end

      it "names the subcommand" do
        run("report", "--input", tmp)

        expect(stderr.string).to include("simplecov report:")
      end

      it "says it cannot read the path" do
        run("report", "--input", tmp)

        expect(stderr.string).to include("cannot read")
      end

      it "names the path" do
        run("report", "--input", tmp)

        expect(stderr.string).to include(tmp)
      end
    end

    context "with a wrong-typed \"groups\"" do
      let(:bad_groups) { File.join(tmp, "bad_groups.json") }

      before { File.write(bad_groups, JSON.dump("total" => {}, "groups" => [1, 2])) }

      it "errors" do
        expect(run("report", "--input", bad_groups)).to eq(1)
      end

      it "says what the field should have been" do
        run("report", "--input", bad_groups)

        expect(stderr.string).to include('"groups" must be an object')
      end

      it "errors in JSON output mode too" do
        expect(run("report", "--json", "--input", bad_groups)).to eq(1)
      end
    end

    context "with a wrong-typed group entry" do
      let(:bad_entry) { File.join(tmp, "bad_group_entry.json") }

      before { File.write(bad_entry, JSON.dump("total" => {}, "groups" => {"Models" => 5})) }

      it "errors" do
        expect(run("report", "--input", bad_entry)).to eq(1)
      end

      it "says what the entries should have been" do
        run("report", "--input", bad_entry)

        expect(stderr.string).to include('"groups" must be an object of objects')
      end
    end

    context "with a wrong-typed \"total\"" do
      let(:bad_total) { File.join(tmp, "bad_total.json") }

      before { File.write(bad_total, JSON.dump("total" => [])) }

      it "errors" do
        expect(run("report", "--input", bad_total)).to eq(1)
      end

      it "says what the field should have been" do
        run("report", "--input", bad_total)

        expect(stderr.string).to include('"total" must be an object')
      end
    end
  end

  describe "coverage subcommand", mutant_expression: ["SimpleCov::CLI::Coverage*", "SimpleCov::CLI::CommandHelpers*"] do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-spec-") }
    let(:json_path) { File.join(tmp, "coverage.json") }
    let(:abs_filename) { "/abs/project/app/models/user.rb" }

    before do
      payload = {
        "coverage" => {
          abs_filename => {
            "lines" => [nil, 1, 1, 0, nil],
            "covered_lines" => 2, "total_lines" => 3, "lines_covered_percent" => 66.67,
            "covered_branches" => 1, "total_branches" => 2, "branches_covered_percent" => 50.0
          }
        }
      }
      File.write(json_path, JSON.dump(payload))
    end

    after { FileUtils.remove_entry(tmp) }

    context "when the report cannot be read" do
      let(:absent) { File.join(tmp, "absent.json") }

      it "errors" do
        expect(run("coverage", "--input", absent, "lib/a.rb")).to eq(1)
      end

      it "names itself and the report in the error" do
        run("coverage", "--input", absent, "lib/a.rb")

        expect(stderr.string).to eq("simplecov coverage: #{absent} not found\n")
      end
    end

    context "when the file is not in the report" do
      it "errors" do
        expect(run("coverage", "--input", json_path, "lib/absent.rb")).to eq(1)
      end

      it "names the report and the path" do
        run("coverage", "--input", json_path, "lib/absent.rb")

        expect(stderr.string).to eq("simplecov coverage: no entry for lib/absent.rb in #{json_path}\n")
      end
    end

    context "with more than one positional argument" do
      it "succeeds" do
        expect(run("coverage", "--input", json_path, abs_filename, "lib/other.rb")).to eq(0)
      end

      it "reads the path from the first" do
        run("coverage", "--input", json_path, abs_filename, "lib/other.rb")

        expect(stdout.string).to include(abs_filename)
      end
    end

    context "when the entry is not an object" do
      before { File.write(json_path, JSON.dump("coverage" => {"lib/a.rb" => "junk"})) }

      it "errors" do
        expect(run("coverage", "--input", json_path, "lib/a.rb")).to eq(1)
      end

      it "names the report and the path" do
        run("coverage", "--input", json_path, "lib/a.rb")

        expect(stderr.string).to eq(
          "simplecov coverage: input file #{json_path.inspect} isn't valid JSON " \
          "(entry for lib/a.rb must be an object)\n"
        )
      end
    end

    context "with a criterion whose counts are missing" do
      before { File.write(json_path, JSON.dump("coverage" => {"lib/a.rb" => {"lines_covered_percent" => 66.67}})) }

      it "succeeds" do
        expect(run("coverage", "--input", json_path, "lib/a.rb")).to eq(0)
      end

      it "prints the criterion with no counts" do
        run("coverage", "--input", json_path, "lib/a.rb")

        expect(stdout.string).to include("(0 / 0)")
      end
    end

    context "with a criterion the report never measured" do
      before do
        File.write(json_path, JSON.dump("coverage" => {"lib/a.rb" => {
          "lines_covered_percent" => 66.67,
          "covered_lines" => 2, "total_lines" => 3
        }}))
      end

      it "succeeds" do
        expect(run("coverage", "--input", json_path, "lib/a.rb")).to eq(0)
      end

      it "prints the criterion it did measure" do
        run("coverage", "--input", json_path, "lib/a.rb")

        expect(stdout.string).to include("Line:")
      end

      it "omits the one it did not" do
        run("coverage", "--input", json_path, "lib/a.rb")

        expect(stdout.string).not_to include("Branch:")
      end
    end

    context "with a percent that arrived as a string" do
      before do
        File.write(json_path, JSON.dump("coverage" => {"lib/a.rb" => {
          "lines_covered_percent" => "66.67",
          "covered_lines" => 2, "total_lines" => 3
        }}))
      end

      it "succeeds" do
        expect(run("coverage", "--input", json_path, "lib/a.rb")).to eq(0)
      end

      it "reads it" do
        run("coverage", "--input", json_path, "lib/a.rb")

        expect(stdout.string).to include("66.67%")
      end
    end

    context "with a matching absolute path" do
      before { run("coverage", "--input", json_path, abs_filename) }

      it "succeeds" do
        expect(run("coverage", "--input", json_path, abs_filename)).to eq(0)
      end

      it "names the file" do
        expect(stdout.string).to include(abs_filename)
      end

      it "prints its line stats" do
        expect(stdout.string).to match(%r{Line:\s+66\.67%\s+\(2 / 3\)})
      end

      it "prints its branch stats" do
        expect(stdout.string).to match(%r{Branch:\s+50\.00%\s+\(1 / 2\)})
      end
    end

    context "with an ambiguous subpath" do
      before do
        File.write(json_path, JSON.dump("coverage" => {
          "/abs/project/app/models/user.rb" => {"lines" => [1]},
          "/abs/project/lib/models/user.rb" => {"lines" => [1]}
        }))
        run("coverage", "--input", json_path, "models/user.rb")
      end

      it "errors" do
        expect(run("coverage", "--input", json_path, "models/user.rb")).to eq(1)
      end

      it "counts the candidates" do
        expect(stderr.string).to include("matches 2 files")
      end

      it "names the first candidate" do
        expect(stderr.string).to include("/abs/project/app/models/user.rb")
      end

      it "names the second candidate" do
        expect(stderr.string).to include("/abs/project/lib/models/user.rb")
      end
    end

    context "with a project-relative path" do
      it "succeeds" do
        expect(run("coverage", "--input", json_path, "app/models/user.rb")).to eq(0)
      end

      it "matches it via end_with on the absolute key" do
        run("coverage", "--input", json_path, "app/models/user.rb")

        expect(stdout.string).to include(abs_filename)
      end
    end

    context "when the input file is missing" do
      it "errors" do
        expect(run("coverage", "--input", "/no/such/coverage.json", "x.rb")).to eq(1)
      end

      it "says so" do
        run("coverage", "--input", "/no/such/coverage.json", "x.rb")

        expect(stderr.string).to include("not found")
      end
    end

    context "when the requested file isn't in the report" do
      it "errors" do
        expect(run("coverage", "--input", json_path, "lib/missing.rb")).to eq(1)
      end

      it "names the path it wanted" do
        run("coverage", "--input", json_path, "lib/missing.rb")

        expect(stderr.string).to include("no entry for lib/missing.rb")
      end
    end

    context "when the matched entry is not an object" do
      before { File.write(json_path, JSON.dump("coverage" => {abs_filename => "junk"})) }

      it "errors" do
        expect(run("coverage", "--input", json_path, abs_filename)).to eq(1)
      end

      it "says what the entry should have been" do
        run("coverage", "--input", json_path, abs_filename)

        expect(stderr.string).to include("entry for #{abs_filename} must be an object")
      end
    end

    context "when the file argument is missing" do
      it "errors" do
        expect(run("coverage", "--input", json_path)).to eq(1)
      end

      it "says so" do
        run("coverage", "--input", json_path)

        expect(stderr.string).to include("missing file argument")
      end
    end

    context "with --json" do
      let(:parsed) { JSON.parse(stdout.string) }

      before { run("coverage", "--input", json_path, "--json", abs_filename) }

      it "succeeds" do
        expect(run("coverage", "--input", json_path, "--json", abs_filename)).to eq(0)
      end

      it "emits the entry under its own key" do
        expect(parsed.keys).to eq([abs_filename])
      end

      it "emits the raw JSON entry" do
        expect(parsed[abs_filename]["lines_covered_percent"]).to eq(66.67)
      end
    end

    context "with colorization" do
      it "succeeds when Color.enabled? is true" do
        allow(SimpleCov::Color).to receive(:enabled?).and_return(true)

        expect(run("coverage", "--input", json_path, abs_filename)).to eq(0)
      end

      it "colorizes percentages when Color.enabled? is true" do
        allow(SimpleCov::Color).to receive(:enabled?).and_return(true)
        run("coverage", "--input", json_path, abs_filename)

        expect(stdout.string).to match(/\e\[31m66\.67%\e\[0m/)
      end

      it_behaves_like "a --no-color subcommand" do
        let(:no_color_argv) { ["coverage", "--input", json_path, "--no-color", abs_filename] }
      end
    end
  end

  describe "run subcommand", mutant_expression: "SimpleCov::CLI::Run*" do
    before do
      allow(described_class::Run).to receive(:exec) { raise "exec reached the module, not Kernel" }
    end

    let(:captured) { {} }

    # Stands in for Kernel#exec, recording the environment and command it was
    # handed so an example can assert on one of them.
    def capture_exec
      allow(Kernel).to receive(:exec) do |env, *cmd|
        captured[:env] = env
        captured[:argv] = cmd
      end
    end

    context "when no command is given" do
      it "exits 1" do
        expect(run("run")).to eq(1)
      end

      it "says what was missing" do
        run("run")

        expect(stderr.string).to eq("simplecov run: missing command\n")
      end
    end

    context "when it execs" do
      before do
        allow(Kernel).to receive(:exec)
        allow(described_class::Run).to receive(:exec)
        described_class::Run.send(:exec_command, {"MARK" => "1"}, ["true", "--flag"])
      end

      it "execs through Kernel by name" do
        expect(Kernel).to have_received(:exec).with({"MARK" => "1"}, "true", "--flag")
      end

      it "never execs through a bare exec on itself" do
        expect(described_class::Run).not_to have_received(:exec)
      end
    end

    context "with a command and its arguments" do
      before do
        capture_exec
        run("run", "echo", "hello")
      end

      it "execs the command" do
        expect(captured[:argv]).to eq(%w[echo hello])
      end

      it "sets RUBYOPT to load the autostart shim" do
        expect(captured[:env]["RUBYOPT"]).to include("-r#{described_class::Run::AUTOSTART}")
      end
    end

    it "passes the whole environment through, not only RUBYOPT" do
      capture_exec

      with_env("SIMPLECOV_SPEC_CARRIED" => "through") { run("run", "true") }

      expect(captured[:env]).to include("SIMPLECOV_SPEC_CARRIED" => "through")
    end

    it "trims an existing RUBYOPT before joining to it" do
      capture_exec

      with_env("RUBYOPT" => "  -W0  ") { run("run", "true") }

      expect(captured[:env]["RUBYOPT"]).to eq("-W0 -r#{described_class::Run::AUTOSTART}")
    end

    it "preserves an existing RUBYOPT alongside the injection" do
      capture_exec

      with_env("RUBYOPT" => "-W0") { run("run", "true") }

      expect(captured[:env]["RUBYOPT"]).to start_with("-W0 -r")
    end

    it "sets RUBYOPT to just the injection when none was already set" do
      capture_exec

      with_env("RUBYOPT" => nil) { run("run", "true") }

      expect(captured[:env]["RUBYOPT"]).to eq("-r#{described_class::Run::AUTOSTART}")
    end

    it "drops a leading -- separator before the command" do
      capture_exec

      run("run", "--", "echo", "hello")

      expect(captured[:argv]).to eq(%w[echo hello])
    end

    context "when the command is not there" do
      before { allow(Kernel).to receive(:exec).and_raise(Errno::ENOENT, "nope") }

      it "answers the shell's own code for it" do
        expect(run("run", "nope")).to eq(127)
      end

      it "reports it" do
        run("run", "nope")

        expect(stderr.string).to eq("simplecov run: No such file or directory - nope\n")
      end
    end

    it "actually starts SimpleCov in a child process" do
      expect(coverage_running_in_a_child.lines.first.strip).to eq("true")
    end

    def coverage_running_in_a_child
      script = <<~RUBY
        require "coverage"
        puts Coverage.running?
      RUBY
      cmd = ["ruby", "-I", File.expand_path("../../lib", __dir__), "-e", script]
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          Open3.capture3({"RUBYOPT" => "-r#{described_class::Run::AUTOSTART}"}, *cmd).first
        end
      end
    end
  end

  describe "report subcommand", mutant_expression: ["SimpleCov::CLI::Report*", "SimpleCov::CLI::CommandHelpers*"] do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-report-spec-") }
    let(:whole_report) do
      <<~TEXT
        All Files
          Line:   80.00% (80 / 100)
          Branch: 90.00% (9 / 10)

        Models
          Line:   80.00% (40 / 50)
          Branch: 100.00% (5 / 5)

        All Files (group)
          Line:   50.00% (1 / 2)

      TEXT
    end
    let(:half_filled_total) do
      {
        "lines" => {"covered" => 8, "total" => 10},
        "branches" => {"percent" => 50.0, "covered" => 1},
        "methods" => {"percent" => 50.0, "total" => 4}
      }
    end
    let(:half_filled_payload) do
      {
        "total" => {
          "lines" => {"percent" => nil, "covered" => 8, "total" => 10},
          "methods" => {"percent" => 50.0, "covered" => nil, "total" => 4}
        },
        "groups" => {"Models" => {}}
      }
    end

    def json_path = File.join(tmp, "coverage.json")

    before do
      File.write(json_path, JSON.dump(
        "total" => {
          "lines" => {"covered" => 80, "total" => 100, "percent" => 80.0},
          "branches" => {"covered" => 9, "total" => 10, "percent" => 90.0},
          "methods" => {"covered" => 0, "total" => 0, "percent" => 100.0}
        },
        "groups" => {
          "Models" => {
            "lines" => {"covered" => 40, "total" => 50, "percent" => 80.0},
            "branches" => {"covered" => 5, "total" => 5, "percent" => 100.0},
            "methods" => {"covered" => 0, "total" => 0, "percent" => 100.0}
          },
          "All Files" => {
            "lines" => {"covered" => 1, "total" => 2, "percent" => 50.0},
            "branches" => {"covered" => 0, "total" => 0, "percent" => 100.0},
            "methods" => {"covered" => 0, "total" => 0, "percent" => 100.0}
          }
        }
      ))
    end

    after { FileUtils.remove_entry(tmp) }

    it "succeeds" do
      expect(run("report", "--input", json_path, "--no-color")).to eq(0)
    end

    it "prints the totals and every group, whole" do
      run("report", "--input", json_path, "--no-color")

      expect(stdout.string).to eq(whole_report)
    end

    context "with the default report" do
      before { run("report", "--input", json_path) }

      it "heads the totals with All Files" do
        expect(stdout.string).to include("All Files")
      end

      it "prints the line totals" do
        expect(stdout.string).to match(%r{Line:\s+80\.00%\s+\(80 / 100\)})
      end

      it "prints the branch totals" do
        expect(stdout.string).to match(%r{Branch:\s+90\.00%\s+\(9 / 10\)})
      end

      it "skips a criterion with zero relevant entries" do
        expect(stdout.string).not_to include("Method:")
      end

      it "prints the group totals" do
        expect(stdout.string).to include("Models")
      end

      it "prints them after the All Files row" do
        expect(stdout.string.index("Models")).to be > stdout.string.index("All Files")
      end

      it "prints the All Files totals row" do
        expect(stdout.string).to include("All Files\n")
      end

      it "labels a user group named All Files distinctly" do
        expect(stdout.string).to include("All Files (group)\n")
      end
    end

    context "with a totals section that is not an object" do
      before { File.write(json_path, JSON.dump("total" => "junk")) }

      it "refuses it" do
        expect(run("report", "--input", json_path)).to eq(1)
      end

      it "says what the section should have been" do
        run("report", "--input", json_path)

        expect(stderr.string)
          .to eq(%(simplecov report: input file #{json_path.inspect} isn't valid JSON ("total" must be an object)\n))
      end
    end

    ["junk", {"Models" => "junk"}].each do |groups|
      context "with #{groups.inspect} for a groups section" do
        before { File.write(json_path, JSON.dump("total" => {}, "groups" => groups)) }

        it "refuses it" do
          expect(run("report", "--input", json_path)).to eq(1)
        end

        it "says what the section should have been" do
          run("report", "--input", json_path)
          prefix = %(simplecov report: input file #{json_path.inspect} isn't valid JSON)

          expect(stderr.string).to eq(%(#{prefix} ("groups" must be an object of objects)\n))
        end
      end
    end

    context "with a report carrying no sections" do
      before { File.write(json_path, JSON.dump({})) }

      it "succeeds" do
        expect(run("report", "--input", json_path)).to eq(0)
      end

      it "prints nothing but a blank line" do
        run("report", "--input", json_path)

        expect(stdout.string).to eq("All Files\n\n")
      end
    end

    context "with a half-filled totals section" do
      before { File.write(json_path, JSON.dump("total" => half_filled_total)) }

      it "succeeds" do
        expect(run("report", "--input", json_path, "--no-color")).to eq(0)
      end

      it "prints what it carries and skips the criterion with no total" do
        run("report", "--input", json_path, "--no-color")

        expect(stdout.string).to eq("All Files\n  Line:   0.00% (8 / 10)\n  Method: 50.00% (0 / 4)\n\n")
      end

      it "carries it into the payload as it stands" do
        File.write(json_path, JSON.dump("total" => half_filled_total,
          "groups" => {"Models" => {"lines" => {"total" => 0}, "branches" => [1, 2]}}))
        run("report", "--input", json_path, "--json")

        expect(JSON.parse(stdout.string)).to eq(half_filled_payload)
      end
    end

    context "with no total and no groups at all" do
      before { File.write(json_path, JSON.dump("coverage" => {})) }

      it "succeeds" do
        expect(run("report", "--input", json_path)).to eq(0)
      end

      it "prints nothing but a blank line" do
        run("report", "--input", json_path)

        expect(stdout.string).to eq("All Files\n\n")
      end

      it "emits an empty payload under --json" do
        run("report", "--input", json_path, "--json")

        expect(JSON.parse(stdout.string)).to eq("total" => {}, "groups" => {})
      end
    end

    context "with a criterion whose section is not an object" do
      before { File.write(json_path, JSON.dump("total" => {"lines" => [1, 2]})) }

      it "succeeds" do
        expect(run("report", "--input", json_path, "--no-color")).to eq(0)
      end

      it "skips it" do
        run("report", "--input", json_path, "--no-color")

        expect(stdout.string).to eq("All Files\n\n")
      end
    end

    it "prints a percentage as reported, to the digit" do
      File.write(json_path, JSON.dump("total" => {"lines" => {"percent" => 66.67, "covered" => 2, "total" => 3}}))
      run("report", "--input", json_path, "--no-color")

      expect(stdout.string).to eq("All Files\n  Line:   66.67% (2 / 3)\n\n")
    end

    context "when the input file is missing" do
      it "errors" do
        expect(run("report", "--input", "/no/such.json")).to eq(1)
      end

      it "names the subcommand" do
        run("report", "--input", "/no/such.json")

        expect(stderr.string).to eq("simplecov report: /no/such.json not found\n")
      end
    end

    context "with --json" do
      let(:payload) { JSON.parse(stdout.string) }

      before { run("report", "--input", json_path, "--json") }

      it "succeeds" do
        expect(run("report", "--input", json_path, "--json")).to eq(0)
      end

      it "emits the namespaced line totals" do
        expect(payload["total"]).to include("lines" => {"percent" => 80.0, "covered" => 80, "total" => 100})
      end

      it "emits the namespaced branch totals" do
        expect(payload["total"]).to include("branches" => {"percent" => 90.0, "covered" => 9, "total" => 10})
      end

      it "leaves out a criterion with zero relevant entries" do
        expect(payload["total"]).not_to include("methods")
      end

      it "emits each group's totals" do
        expect(payload.dig("groups", "Models"))
          .to include("lines" => {"percent" => 80.0, "covered" => 40, "total" => 50})
      end

      it "emits a user group named All Files under its own name" do
        expect(payload.dig("groups", "All Files"))
          .to include("lines" => {"percent" => 50.0, "covered" => 1, "total" => 2})
      end
    end

    context "with colorization" do
      before { allow(SimpleCov::Color).to receive(:enabled?).and_return(true) }

      it "succeeds when Color.enabled? is true" do
        expect(run("report", "--input", json_path)).to eq(0)
      end

      it "colorizes a percentage under the top threshold" do
        run("report", "--input", json_path)

        expect(stdout.string).to match(/\e\[33m80\.00%\e\[0m/)
      end

      it "colorizes a percentage over it" do
        run("report", "--input", json_path)

        expect(stdout.string).to match(/\e\[32m90\.00%\e\[0m/)
      end

      it "colorizes a group's percentages too, not just the totals row" do
        run("report", "--input", json_path)

        expect(stdout.string.split("Models\n").last).to match(/\e\[33m80\.00%\e\[0m/)
      end

      it_behaves_like "a --no-color subcommand" do
        let(:no_color_argv) { ["report", "--input", json_path, "--no-color"] }
      end
    end
  end

  describe "tests subcommand", mutant_expression: ["SimpleCov::CLI::Tests*", "SimpleCov::CLI::CommandHelpers*"] do
    include_context "with a tests report"

    let(:payload) do
      {
        "contexts" => ["spec/result_spec.rb:42", "spec/result_spec.rb:57"],
        "coverage" => {
          result_file => {"lines" => [nil, 1, 2, 0], "contexts" => {"0" => "6", "1" => "4"}},
          quiet_file => {"lines" => [1, nil]}
        }
      }
    end

    it "succeeds with a bare invocation" do
      expect(run("tests", "--input", json_path)).to eq(0)
    end

    it "lists every recorded test, sorted, with a bare invocation" do
      run("tests", "--input", json_path)

      expect(stdout.string).to eq("spec/result_spec.rb:42\nspec/result_spec.rb:57\n")
    end

    it "succeeds for a file" do
      expect(run("tests", "--input", json_path, "lib/result.rb")).to eq(0)
    end

    it "narrows to the tests touching a file" do
      run("tests", "--input", json_path, "lib/result.rb")

      expect(stdout.string).to eq("spec/result_spec.rb:42\nspec/result_spec.rb:57\n")
    end

    it "succeeds for one line" do
      expect(run("tests", "--input", json_path, "lib/result.rb:2")).to eq(0)
    end

    it "narrows to the tests covering one line" do
      run("tests", "--input", json_path, "lib/result.rb:2")

      expect(stdout.string).to eq("spec/result_spec.rb:42\n")
    end

    context "with a line no test covers" do
      before { run("tests", "--input", json_path, "lib/result.rb:4") }

      it "succeeds" do
        expect(run("tests", "--input", json_path, "lib/result.rb:4")).to eq(0)
      end

      it "answers an empty list" do
        expect(stdout.string).to be_empty
      end

      it "notes that on stderr" do
        expect(stderr.string).to eq("simplecov tests: no recorded test covers lib/result.rb:4\n")
      end
    end

    context "with a covered file no recorded context touched" do
      before { run("tests", "--input", json_path, "lib/quiet.rb") }

      it "succeeds" do
        expect(run("tests", "--input", json_path, "lib/quiet.rb")).to eq(0)
      end

      it "answers an empty list" do
        expect(stdout.string).to be_empty
      end

      it "notes that on stderr" do
        expect(stderr.string).to eq("simplecov tests: no recorded test covers lib/quiet.rb\n")
      end
    end

    context "with --json" do
      it "succeeds" do
        expect(run("tests", "--input", json_path, "--json", "lib/result.rb:3")).to eq(0)
      end

      it "emits a JSON array" do
        run("tests", "--input", json_path, "--json", "lib/result.rb:3")

        expect(JSON.parse(stdout.string)).to eq(["spec/result_spec.rb:42", "spec/result_spec.rb:57"])
      end

      it "succeeds for an empty result" do
        expect(run("tests", "--input", json_path, "--json", "lib/result.rb:4")).to eq(0)
      end

      it "emits an empty JSON array for an empty result" do
        run("tests", "--input", json_path, "--json", "lib/result.rb:4")

        expect(JSON.parse(stdout.string)).to eq([])
      end

      it "says nothing on stderr for an empty result" do
        run("tests", "--input", json_path, "--json", "lib/result.rb:4")

        expect(stderr.string).to be_empty
      end
    end

    context "with an empty recording" do
      before do
        File.write(json_path, JSON.dump(payload.merge("contexts" => [])))
        run("tests", "--input", json_path)
      end

      it "succeeds" do
        expect(run("tests", "--input", json_path)).to eq(0)
      end

      it "answers an empty list" do
        expect(stdout.string).to be_empty
      end

      it "notes it on stderr" do
        expect(stderr.string).to eq("simplecov tests: no tests recorded\n")
      end
    end

    context "when the document carries no contexts" do
      before { File.write(json_path, JSON.dump({"coverage" => {}})) }

      it "errors" do
        expect(run("tests", "--input", json_path)).to eq(1)
      end

      it "explains what to enable" do
        run("tests", "--input", json_path)

        expect(stderr.string).to eq(
          "simplecov tests: no test contexts recorded in #{json_path}. Enable `track_tests` in " \
          "your `SimpleCov.start` block and rerun the suite to record them\n"
        )
      end
    end

    context "with a wrong-typed entry" do
      before { File.write(json_path, JSON.dump(payload.merge("coverage" => {result_file => "junk"}))) }

      it "errors" do
        expect(run("tests", "--input", json_path, "lib/result.rb")).to eq(1)
      end

      it "reports it as invalid input, not as missing" do
        run("tests", "--input", json_path, "lib/result.rb")

        expect(stderr.string).to eq(
          "simplecov tests: input file #{json_path.inspect} isn't valid JSON " \
          "(entry for lib/result.rb must be an object)\n"
        )
      end
    end

    it "documents its --json in the usage text" do
      run("help")

      expect(stdout.string).to include("tests options:")
    end

    context "with an unknown file" do
      it "errors" do
        expect(run("tests", "--input", json_path, "lib/nope.rb")).to eq(1)
      end

      it "reports it like the coverage subcommand does" do
        run("tests", "--input", json_path, "lib/nope.rb")

        expect(stderr.string).to eq("simplecov tests: no entry for lib/nope.rb in #{json_path}\n")
      end
    end

    context "with an ambiguous subpath" do
      before do
        payload["coverage"][result_file.sub("/lib/", "/app/")] = {"lines" => [1]}
        File.write(json_path, JSON.dump(payload))
      end

      it "errors" do
        expect(run("tests", "--input", json_path, "result.rb")).to eq(1)
      end

      it "names the candidates" do
        run("tests", "--input", json_path, "result.rb")

        expect(stderr.string).to eq(
          "simplecov tests: result.rb matches 2 files in #{json_path}: " \
          "/abs/project/app/result.rb, /abs/project/lib/result.rb (use a longer path to pick one)\n"
        )
      end
    end

    context "with a non-positive line number" do
      it "errors" do
        expect(run("tests", "--input", json_path, "lib/result.rb:0")).to eq(1)
      end

      it "rejects it as a parse error" do
        run("tests", "--input", json_path, "lib/result.rb:0")

        expect(stderr.string).to eq("simplecov tests: line number must be positive\n")
      end
    end

    context "with a missing input file" do
      let(:missing) { File.join(tmp, "nope.json") }

      it "errors" do
        expect(run("tests", "--input", missing)).to eq(1)
      end

      it "reports it under its own command name" do
        run("tests", "--input", missing)

        expect(stderr.string).to eq("simplecov tests: #{missing} not found\n")
      end
    end

    [{"9" => "6"}, {"x" => "6"}, {"0" => "zz"}, "junk"].each do |malformed|
      context "with #{malformed.inspect} for a per-file contexts table" do
        before do
          payload["coverage"][result_file]["contexts"] = malformed
          File.write(json_path, JSON.dump(payload))
        end

        it "errors" do
          expect(run("tests", "--input", json_path, "lib/result.rb")).to eq(1)
        end

        it "treats it as invalid input" do
          run("tests", "--input", json_path, "lib/result.rb")

          expect(stderr.string).to eq(
            "simplecov tests: input file #{json_path.inspect} isn't valid JSON " \
            "(entry for lib/result.rb carries a malformed \"contexts\" table)\n"
          )
        end
      end
    end

    context "with a non-object coverage section" do
      before { File.write(json_path, JSON.dump(payload.merge("coverage" => "junk"))) }

      it "errors on a file query" do
        expect(run("tests", "--input", json_path, "lib/result.rb")).to eq(1)
      end

      it "treats it as invalid input" do
        run("tests", "--input", json_path, "lib/result.rb")

        expect(stderr.string).to eq(
          %(simplecov tests: input file #{json_path.inspect} isn't valid JSON ("coverage" must be an object)\n)
        )
      end
    end

    context "with no coverage section at all" do
      before { File.write(json_path, JSON.dump({"contexts" => payload["contexts"]})) }

      it "errors on a file query" do
        expect(run("tests", "--input", json_path, "lib/result.rb")).to eq(1)
      end

      it "treats it as invalid input" do
        run("tests", "--input", json_path, "lib/result.rb")

        expect(stderr.string).to eq(
          %(simplecov tests: input file #{json_path.inspect} isn't valid JSON ("coverage" must be an object)\n)
        )
      end
    end

    context "with a malformed document-level contexts list" do
      before { File.write(json_path, JSON.dump(payload.merge("contexts" => "junk"))) }

      it "errors" do
        expect(run("tests", "--input", json_path)).to eq(1)
      end

      it "treats it as invalid input" do
        run("tests", "--input", json_path)

        expect(stderr.string).to eq(
          %(simplecov tests: input file #{json_path.inspect} isn't valid JSON ("contexts" must be an array of strings)\n)
        )
      end
    end

    describe "query helpers" do
      let(:tests) { SimpleCov::CLI::Tests }

      {
        nil => {path: nil, line: nil},
        "a.rb" => {path: "a.rb", line: nil},
        "a.rb:42" => {path: "a.rb", line: 42},
        "a.rb:4x" => {path: "a.rb:4x", line: nil},
        "C:/x.rb" => {path: "C:/x.rb", line: nil},
        "a.rb:42:7" => {path: "a.rb:42", line: 7}
      }.each do |target, split|
        it "splits #{target.inspect} the way the docs promise" do
          expect(tests.split_target(target)).to eq(split)
        end
      end

      it "decodes well-formed index and bitmap pairs, multi-digit and zero-padded included" do
        expect(tests.decode_table({"2" => "ff", "0" => "1", "10" => "a", "08" => "1"}, 11))
          .to eq(2 => 255, 0 => 1, 10 => 10, 8 => 1)
      end

      it "poisons the whole table on any malformed index or bitmap" do
        malformed = [{"1" => "6"}, {"x" => "6"}, {"0abc" => "1"}, {"abc0" => "1"},
          {"0" => "zz"}, {"0" => "6g"}, {"0" => "g6"}, {0 => "6"}, {"0" => 6}]
        expect(malformed.map { |raw| tests.decode_table(raw, 1) }).to all(be_nil)
      end

      it "selects ids by line bit" do
        expect(tests.ids_from({0 => 0b10, 1 => 0b01}, %w[b a], 2)).to eq(["b"])
      end

      it "selects all ids, sorted, without a line" do
        expect(tests.ids_from({1 => 0b1, 0 => 0b1}, %w[a z], nil)).to eq(%w[a z])
      end

      it "keeps the first positional argument as the target" do
        expect(tests.parse(["a.rb:1", "z.rb:2"])).to include(target: "a.rb:1", path: "a.rb", line: 1)
      end

      it "reads an all-digit target as a path, not a line" do
        expect(tests.split_target("42")).to eq(path: "42", line: nil)
      end

      it "reads a zero-padded line number in base ten" do
        expect(tests.split_target("a.rb:08")).to eq(path: "a.rb", line: 8)
      end

      it "answers nothing for an empty answer" do
        expect(tests.emit([], {json: false, target: nil, redundant: nil}, StringIO.new, StringIO.new)).to be_nil
      end

      it "keeps ids the answer's only stdout even for an empty answer" do
        out = StringIO.new
        tests.emit([], {json: false, target: nil, redundant: nil}, out, StringIO.new)

        expect(out.string).to be_empty
      end

      it "ignores a redundant key whose value says off" do
        document = {"contexts" => %w[a b], "coverage" => {"/f.rb" => {"contexts" => {"0" => "1"}}}}
        opts = {path: nil, line: nil, redundant: nil, input: "x"}
        expect(tests.resolve(document, opts, StringIO.new)).to eq(%w[a b])
      end

      it "accepts String subclasses in a decoded table" do
        subclass = Class.new(String)
        expect(tests.decode_table({subclass.new("0") => subclass.new("6")}, 1)).to eq(0 => 6)
      end

      it "reads the redundant decision from the value, not the key's presence" do
        expect(tests.empty_message({redundant: nil, target: "t"})).to eq("no recorded test covers t")
      end

      it "answers nothing for a defective document under --redundant" do
        document = {"contexts" => ["t"], "coverage" => "junk"}

        expect(tests.resolve(document, {path: "p", redundant: true, input: "i"}, StringIO.new)).to be_nil
      end

      it "stops at the first reported defect even under --redundant" do
        io = StringIO.new
        tests.resolve({"contexts" => ["t"], "coverage" => "junk"}, {path: "p", redundant: true, input: "i"}, io)

        expect(io.string.lines.count).to eq(1)
      end

      it "locates the very entry through Hash-subclass document sections" do
        subclass = Class.new(Hash)
        entry = subclass.new.merge!("contexts" => {"0" => "1"})
        coverage = subclass.new.merge!("/abs/x.rb" => entry)
        opts = {path: "/abs/x.rb", input: "x"}
        expect(tests.locate_entry({"coverage" => coverage}, opts, StringIO.new)).to equal(entry)
      end

      it "reads an absent contexts key as an empty table" do
        expect(tests.context_table({}, [], {}, StringIO.new)).to eq({})
      end

      it "reads a Hash-subclass contexts key for the file's table" do
        raw = Class.new(Hash).new.merge!("0" => "6")

        expect(tests.context_table({"contexts" => raw}, ["a"], {}, StringIO.new)).to eq(0 => 6)
      end
    end
  end

  describe "tests subcommand --redundant", mutant_expression: ["SimpleCov::CLI::Tests*", "SimpleCov::CLI::CommandHelpers*"] do
    include_context "with a tests report"

    let(:payload) do
      {
        "contexts" => ["spec/d_spec.rb:40", "spec/a_spec.rb:10", "spec/b_spec.rb:20", "spec/c_spec.rb:30"],
        "coverage" => {
          result_file => {"lines" => [nil, 1, 2, 0], "contexts" => {"1" => "6", "2" => "4"}},
          other_file => {"lines" => [1], "contexts" => {"3" => "1"}},
          quiet_file => {"lines" => [1, nil]}
        }
      }
    end

    def other_file = "/abs/project/lib/other.rb"

    it "succeeds" do
      expect(run("tests", "--input", json_path, "--redundant")).to eq(0)
    end

    it "lists the tests whose covered lines other tests also cover" do
      run("tests", "--input", json_path, "--redundant")

      expect(stdout.string).to eq("spec/b_spec.rb:20\nspec/d_spec.rb:40\n")
    end

    it "succeeds for a file" do
      expect(run("tests", "--input", json_path, "--redundant", "lib/result.rb")).to eq(0)
    end

    it "narrows to the redundant tests touching a file" do
      run("tests", "--input", json_path, "--redundant", "lib/result.rb")

      expect(stdout.string).to eq("spec/b_spec.rb:20\n")
    end

    context "with a line only unique tests cover" do
      before { run("tests", "--input", json_path, "--redundant", "lib/result.rb:2") }

      it "succeeds" do
        expect(run("tests", "--input", json_path, "--redundant", "lib/result.rb:2")).to eq(0)
      end

      it "answers an empty list" do
        expect(stdout.string).to be_empty
      end

      it "notes it on stderr" do
        expect(stderr.string).to eq("simplecov tests: no redundant test covers lib/result.rb:2\n")
      end
    end

    it "lists both of two tests covering exactly the same lines" do
      payload["coverage"][result_file]["contexts"] = {"1" => "6", "2" => "6"}
      File.write(json_path, JSON.dump(payload))
      run("tests", "--input", json_path, "--redundant")

      expect(stdout.string).to eq("spec/a_spec.rb:10\nspec/b_spec.rb:20\nspec/d_spec.rb:40\n")
    end

    context "when every recorded test covers something uniquely" do
      before do
        File.write(json_path, JSON.dump(
          "contexts" => ["spec/a_spec.rb:10", "spec/c_spec.rb:30"],
          "coverage" => {result_file => {"lines" => [1, 1],
                                         "contexts" => {"0" => "1", "1" => "2"}}}
        ))
        run("tests", "--input", json_path, "--redundant")
      end

      it "succeeds" do
        expect(run("tests", "--input", json_path, "--redundant")).to eq(0)
      end

      it "answers an empty list" do
        expect(stdout.string).to be_empty
      end

      it "notes it on stderr" do
        expect(stderr.string)
          .to eq("simplecov tests: no redundant tests, every recorded test covers at least one line uniquely\n")
      end
    end

    context "when the contexts list is empty" do
      before do
        File.write(json_path, JSON.dump("contexts" => [], "coverage" => {quiet_file => {"lines" => [1, nil]}}))
        run("tests", "--input", json_path, "--redundant")
      end

      it "succeeds" do
        expect(run("tests", "--input", json_path, "--redundant")).to eq(0)
      end

      it "answers an empty list" do
        expect(stdout.string).to be_empty
      end

      it "keeps the no-recording note" do
        expect(stderr.string).to eq("simplecov tests: no tests recorded\n")
      end
    end

    it "succeeds under --json" do
      expect(run("tests", "--input", json_path, "--redundant", "--json")).to eq(0)
    end

    it "emits the redundant ids as a JSON array under --json" do
      run("tests", "--input", json_path, "--redundant", "--json")

      expect(JSON.parse(stdout.string)).to eq(["spec/b_spec.rb:20", "spec/d_spec.rb:40"])
    end

    [{"9" => "1"}, "junk"].each do |malformed|
      context "with #{malformed.inspect} for a contexts table in the sweep" do
        before do
          payload["coverage"][other_file]["contexts"] = malformed
          File.write(json_path, JSON.dump(payload))
        end

        it "errors" do
          expect(run("tests", "--input", json_path, "--redundant")).to eq(1)
        end

        it "treats it as invalid input" do
          run("tests", "--input", json_path, "--redundant")

          expect(stderr.string).to eq(
            %(simplecov tests: input file #{json_path.inspect} isn't valid JSON ) +
            %[(entry for #{other_file} carries a malformed "contexts" table)\n]
          )
        end
      end
    end

    context "with a non-object coverage section" do
      before { File.write(json_path, JSON.dump(payload.merge("coverage" => "junk"))) }

      it "errors on the bare sweep" do
        expect(run("tests", "--input", json_path, "--redundant")).to eq(1)
      end

      it "treats it as invalid input" do
        run("tests", "--input", json_path, "--redundant")

        expect(stderr.string).to eq(
          %(simplecov tests: input file #{json_path.inspect} isn't valid JSON ("coverage" must be an object)\n)
        )
      end
    end

    context "with no coverage section at all" do
      before { File.write(json_path, JSON.dump({"contexts" => payload["contexts"]})) }

      it "errors on the bare sweep" do
        expect(run("tests", "--input", json_path, "--redundant")).to eq(1)
      end

      it "treats it like any other non-object one" do
        run("tests", "--input", json_path, "--redundant")

        expect(stderr.string).to eq(
          %(simplecov tests: input file #{json_path.inspect} isn't valid JSON ("coverage" must be an object)\n)
        )
      end
    end

    context "with a wrong-typed entry in the sweep" do
      before do
        payload["coverage"][quiet_file] = "junk"
        File.write(json_path, JSON.dump(payload))
      end

      it "errors" do
        expect(run("tests", "--input", json_path, "--redundant")).to eq(1)
      end

      it "treats it as invalid input" do
        run("tests", "--input", json_path, "--redundant")

        expect(stderr.string).to eq(
          %(simplecov tests: input file #{json_path.inspect} isn't valid JSON ) +
          %((entry for #{quiet_file} must be an object)\n)
        )
      end
    end

    describe "sweep helpers" do
      let(:redundancy) { SimpleCov::CLI::Tests::Redundancy }

      {
        {} => 0,
        {0 => 0b1} => 0b1,
        {0 => 0b0110, 1 => 0b0100, 2 => 0b1100} => 0b1010,
        {0 => 0b1, 1 => 0b1, 2 => 0b1} => 0
      }.each do |bitmaps, lone|
        it "extracts the bits set in exactly one of #{bitmaps.inspect}" do
          expect(redundancy.lone_bits(bitmaps)).to eq(lone)
        end
      end

      it "credits a uniquely covered bit to its owning context" do
        expect(redundancy.unique_owners([{0 => 0b11, 1 => 0b10}], 3)).to eq([true, false, false])
      end

      it "credits each file's own uniquely covered bit" do
        expect(redundancy.unique_owners([{0 => 0b1}, {1 => 0b10}], 2)).to eq([true, true])
      end

      it "decodes a table arriving as a Hash subclass" do
        raw = Class.new(Hash).new
        raw["0"] = "6"
        expect(redundancy.swept_table({"contexts" => raw}, ["spec/a_spec.rb:1"])).to eq(0 => 6)
      end

      it "complains about the table, not the entry, for a Hash-subclass entry" do
        entry = Class.new(Hash).new

        expect(redundancy.complaint("/p.rb", entry))
          .to eq(%(entry for /p.rb carries a malformed "contexts" table))
      end

      it "complains about the entry for anything that is not a Hash at all" do
        expect(redundancy.complaint("/p.rb", "junk")).to eq("entry for /p.rb must be an object")
      end

      it "answers nothing for an invalid document" do
        expect(redundancy.invalid({input: nil}, StringIO.new, "why")).to be_nil
      end

      it "renders a nil input path rather than raising" do
        io = StringIO.new
        redundancy.invalid({input: nil}, io, "why")

        expect(io.string).to eq(%(simplecov tests: input file nil isn't valid JSON (why)\n))
      end

      it "sweeps a document built from Hash subclasses" do
        subclass = Class.new(Hash)
        raw = subclass.new.merge!("0" => "1")
        entry = subclass.new.merge!("contexts" => raw)
        coverage = subclass.new.merge!("/f.rb" => entry)
        expect(redundancy.sweep_tables({"coverage" => coverage}, ["a"], {input: "x"}, StringIO.new)).to eq([{0 => 1}])
      end

      it "answers sorted ids regardless of the recording order" do
        document = {"coverage" => {"/f.rb" => {"contexts" => {"2" => "1"}}}}
        contexts = ["z_spec.rb:9", "m_spec.rb:5", "a_spec.rb:1"]
        expect(redundancy.redundant_ids(document, contexts, {input: "x"}, StringIO.new))
          .to eq(["m_spec.rb:5", "z_spec.rb:9"])
      end
    end

    it "documents --redundant in the usage text" do
      run("help")

      expect(stdout.string).to include("--redundant")
    end
  end

  describe "show subcommand", mutant_expression: "SimpleCov::CLI::Show*" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-show-spec-") }
    let(:entry) do
      {
        "source" => source,
        "lines" => [1, 1, 0, nil, nil, 0, 0, 0, 1, 0],
        "branches" => [{"report_line" => 2, "coverage" => 0}, {"report_line" => 1, "coverage" => 3}, "junk"],
        "methods" => [{"start_line" => 1, "coverage" => 0}, {"start_line" => "x", "coverage" => 0}, "junk"]
      }
    end
    let(:payload) { {"coverage" => {code_path => entry}} }

    def source
      ["def call(baseline)", "  rows = compare", "  return 1 if rows.empty?", "",
        "# comment", "again", "done", "more", "covered", "last"]
    end

    def annotated_source
      <<~OUT
         1  1  def call(baseline)
               ^ method missed
         2  1    rows = compare
               ^ branch missed
         3  0    return 1 if rows.empty?
               ^ missed
         4
         5     # comment
         6  0  again
               ^ missed
         7  0  done
               ^ missed
         8  0  more
               ^ missed
         9  1  covered
        10  0  last
               ^ missed
      OUT
    end

    def json_path = File.join(tmp, "coverage.json")

    def code_path = File.join(tmp, "lib/code.rb")

    before { File.write(json_path, JSON.dump(payload)) }

    after { FileUtils.rm_rf(tmp) }

    it "succeeds" do
      expect(run("show", "--input", json_path, "lib/code.rb")).to eq(0)
    end

    it "prints the source with hit counts and miss markers" do
      run("show", "--input", json_path, "lib/code.rb")

      expect(stdout.string).to eq(annotated_source)
    end

    it "joins a line's markers when it misses more than one way" do
      entry["branches"][0]["report_line"] = 3
      File.write(json_path, JSON.dump(payload))
      run("show", "--input", json_path, "lib/code.rb")

      expect(stdout.string).to include("^ missed, branch missed")
    end

    it "succeeds under --uncovered-only" do
      expect(run("show", "--input", json_path, "--uncovered-only", "lib/code.rb")).to eq(0)
    end

    it "collapses the misses to greppable ranges under --uncovered-only" do
      run("show", "--input", json_path, "--uncovered-only", "lib/code.rb")

      expect(stdout.string).to eq("lib/code.rb:3,6-8,10\n")
    end

    context "with more files than the one asked for" do
      before do
        payload["coverage"][File.join(SimpleCov.root, "lib/zzz.rb")] = {"lines" => [0]}
        payload["coverage"][File.join(SimpleCov.root, "lib/rooted.rb")] = {"lines" => [1, 0, 0, nil, 0]}
        payload["coverage"][File.join(tmp, "lib/covered.rb")] = {"lines" => [1, 1]}
        payload["coverage"][File.join(tmp, "lib/junk.rb")] = "junk"
        File.write(json_path, JSON.dump(payload))
      end

      it "succeeds" do
        expect(run("show", "--input", json_path, "--uncovered-only")).to eq(0)
      end

      it "sweeps the whole project under a bare --uncovered-only" do
        run("show", "--input", json_path, "--uncovered-only")

        expect(stdout.string).to eq(<<~OUT)
          #{code_path}:3,6-8,10
          lib/rooted.rb:2-3,5
          lib/zzz.rb:1
        OUT
      end
    end

    context "with a missing input" do
      let(:missing) { File.join(tmp, "nope.json") }

      it "errors on a bare sweep" do
        expect(run("show", "--input", missing, "--uncovered-only")).to eq(1)
      end

      it "reports it on a bare sweep like everywhere else" do
        run("show", "--input", missing, "--uncovered-only")

        expect(stderr.string).to eq("simplecov show: #{missing} not found\n")
      end

      it "errors for one file" do
        expect(run("show", "--input", missing, "lib/code.rb")).to eq(1)
      end

      it "names the subcommand and the input" do
        run("show", "--input", missing, "lib/code.rb")

        expect(stderr.string).to eq("simplecov show: #{missing} not found\n")
      end
    end

    context "with entries whose lines are no lines at all" do
      before do
        payload["coverage"][File.join(tmp, "lib/odd.rb")] = {"lines" => "junk"}
        payload["coverage"][File.join(tmp, "lib/list.rb")] = [1, 0]
        payload["coverage"][File.join(tmp, "lib/none.rb")] = {"branches" => []}
        File.write(json_path, JSON.dump(payload))
      end

      it "succeeds" do
        expect(run("show", "--input", json_path, "--uncovered-only")).to eq(0)
      end

      it "passes over them in a sweep" do
        run("show", "--input", json_path, "--uncovered-only")

        expect(stdout.string).to eq("#{code_path}:3,6-8,10\n")
      end
    end

    context "with an unexpanded root" do
      before { allow(SimpleCov).to receive(:root).and_return(File.join(tmp, "lib", "..")) }

      it "succeeds" do
        expect(run("show", "--input", json_path, "--uncovered-only")).to eq(0)
      end

      it "trims it off the paths it sweeps" do
        run("show", "--input", json_path, "--uncovered-only")

        expect(stdout.string).to eq("lib/code.rb:3,6-8,10\n")
      end
    end

    context "with a fully covered project" do
      before do
        entry["lines"] = [1, 1, 1, nil, nil, 1, 1, 1, 1, 1]
        File.write(json_path, JSON.dump(payload))
      end

      it "succeeds under a bare --uncovered-only" do
        expect(run("show", "--input", json_path, "--uncovered-only")).to eq(0)
      end

      it "prints nothing under a bare --uncovered-only" do
        run("show", "--input", json_path, "--uncovered-only")

        expect(stdout.string).to be_empty
      end

      it "notes it on stderr" do
        run("show", "--input", json_path, "--uncovered-only")

        expect(stderr.string).to eq("simplecov show: nothing uncovered\n")
      end

      it "prints nothing for one file under --uncovered-only" do
        run("show", "--input", json_path, "--uncovered-only", "lib/code.rb")

        expect(stdout.string).to be_empty
      end

      it "notes the file on stderr" do
        run("show", "--input", json_path, "--uncovered-only", "lib/code.rb")

        expect(stderr.string).to eq("simplecov show: nothing uncovered in lib/code.rb\n")
      end
    end

    it "succeeds on a project sweep under --json" do
      expect(run("show", "--input", json_path, "--json")).to eq(0)
    end

    it "emits the project sweep as JSON" do
      run("show", "--input", json_path, "--json")

      expect(JSON.parse(stdout.string)).to eq([{"path" => code_path, "missed" => [3, 6, 7, 8, 10]}])
    end

    context "when the report carries no source" do
      before do
        entry.delete("source")
        entry.delete("branches")
        entry.delete("methods")
        File.write(json_path, JSON.dump(payload))
        FileUtils.mkdir_p(File.dirname(code_path))
        File.write(code_path, "#{source.join("\n")}\n")
      end

      it "succeeds" do
        expect(run("show", "--input", json_path, "lib/code.rb")).to eq(0)
      end

      it "reads the source from disk" do
        run("show", "--input", json_path, "lib/code.rb")

        expect(stdout.string).to include("  return 1 if rows.empty?")
      end

      it "marks nothing it has no data for" do
        run("show", "--input", json_path, "lib/code.rb")

        expect(stdout.string).not_to include("branch missed")
      end
    end

    context "when the disk source drifted from the report" do
      before do
        entry.delete("source")
        File.write(json_path, JSON.dump(payload))
        FileUtils.mkdir_p(File.dirname(code_path))
        File.write(code_path, "one\ntwo\n")
      end

      it "refuses it" do
        expect(run("show", "--input", json_path, "lib/code.rb")).to eq(1)
      end

      it "says why" do
        run("show", "--input", json_path, "lib/code.rb")

        expect(stderr.string).to include("changed since the report")
      end
    end

    context "when neither the report nor the disk has the source" do
      before do
        entry.delete("source")
        File.write(json_path, JSON.dump(payload))
      end

      it "errors" do
        expect(run("show", "--input", json_path, "lib/code.rb")).to eq(1)
      end

      it "says to regenerate the report" do
        run("show", "--input", json_path, "lib/code.rb")

        expect(stderr.string).to include("regenerate")
      end

      it "answers JSON without any source available" do
        run("show", "--input", json_path, "--json", "lib/code.rb")

        expect(JSON.parse(stdout.string)["missed"]).to eq([3, 6, 7, 8, 10])
      end

      it "succeeds under --json" do
        expect(run("show", "--input", json_path, "--json", "lib/code.rb")).to eq(0)
      end
    end

    context "with a report without line data" do
      before do
        entry.delete("lines")
        File.write(json_path, JSON.dump(payload))
      end

      it "errors" do
        expect(run("show", "--input", json_path, "lib/code.rb")).to eq(1)
      end

      it "says so" do
        run("show", "--input", json_path, "lib/code.rb")

        expect(stderr.string).to eq("simplecov show: no line coverage for lib/code.rb in #{json_path}\n")
      end
    end

    context "with a report whose line data is no list" do
      before do
        entry["lines"] = "junk"
        File.write(json_path, JSON.dump(payload))
      end

      it "errors" do
        expect(run("show", "--input", json_path, "lib/code.rb")).to eq(1)
      end

      it "says so" do
        run("show", "--input", json_path, "lib/code.rb")

        expect(stderr.string).to eq("simplecov show: no line coverage for lib/code.rb in #{json_path}\n")
      end
    end

    context "with an unknown file" do
      it "errors" do
        expect(run("show", "--input", json_path, "lib/nope.rb")).to eq(1)
      end

      it "reports it like the coverage subcommand does" do
        run("show", "--input", json_path, "lib/nope.rb")

        expect(stderr.string).to eq("simplecov show: no entry for lib/nope.rb in #{json_path}\n")
      end
    end

    context "with a wrong-typed entry" do
      before { File.write(json_path, JSON.dump("coverage" => {code_path => "junk"})) }

      it "errors" do
        expect(run("show", "--input", json_path, "lib/code.rb")).to eq(1)
      end

      it "reports it as invalid input" do
        run("show", "--input", json_path, "lib/code.rb")

        expect(stderr.string).to eq(
          "simplecov show: input file #{json_path.inspect} isn't valid JSON " \
          "(entry for lib/code.rb must be an object)\n"
        )
      end
    end

    context "without a path" do
      it "errors" do
        expect(run("show", "--input", json_path)).to eq(1)
      end

      it "says what was missing" do
        run("show", "--input", json_path)

        expect(stderr.string).to include("missing path")
      end
    end

    context "with colorization" do
      before { allow(SimpleCov::Color).to receive(:enabled?).and_return(true) }

      it "succeeds" do
        expect(run("show", "--input", json_path, "lib/code.rb")).to eq(0)
      end

      it "colorizes the misses" do
        run("show", "--input", json_path, "lib/code.rb")

        expect(stdout.string).to include("\e[31m")
      end

      it "colorizes the hits" do
        run("show", "--input", json_path, "lib/code.rb")

        expect(stdout.string).to include("\e[32m")
      end
    end

    context "with --json for one file" do
      let(:parsed) { JSON.parse(stdout.string) }

      before { run("show", "--input", json_path, "--json", "lib/code.rb") }

      it "succeeds" do
        expect(run("show", "--input", json_path, "--json", "lib/code.rb")).to eq(0)
      end

      it "names the path" do
        expect(parsed["path"]).to eq("lib/code.rb")
      end

      it "lists the missed lines" do
        expect(parsed["missed"]).to eq([3, 6, 7, 8, 10])
      end

      it "lists the relevant lines" do
        expect(parsed["lines"].size).to eq(8)
      end

      it "carries each line's number and hits" do
        expect(parsed["lines"].first).to eq("number" => 1, "hits" => 1)
      end

      it "carries the markers" do
        expect(parsed["markers"]).to include("1" => ["method missed"], "2" => ["branch missed"], "3" => ["missed"])
      end
    end

    it_behaves_like "a --no-color subcommand" do
      let(:no_color_argv) { ["show", "--input", json_path, "--no-color", "lib/code.rb"] }
    end

    it "documents itself in the usage text" do
      run("help")

      expect(stdout.string).to include("show options:")
    end

    describe ".source_for" do
      it "reads the file from disk without the newlines" do
        FileUtils.mkdir_p(File.dirname(code_path))
        File.write(code_path, source.join("\n") << "\n")
        entry.delete("source")

        read = SimpleCov::CLI::Show.source_for(code_path, entry, {path: "lib/code.rb", input: json_path}, stderr)
        expect(read).to eq(source)
      end
    end

    describe ".parse" do
      it "reads the project's own report when no input is named" do
        expect(SimpleCov::CLI::Show.parse([])[:input]).to eq(described_class.default_input)
      end

      it "counts only whole numbers of hits as lines to report" do
        entry["lines"] = [1, 0.0, "3", nil, 5]
        File.write(json_path, JSON.dump(payload))
        run("show", "--input", json_path, "--json", "lib/code.rb")

        expect(JSON.parse(stdout.string)["lines"])
          .to eq([{"number" => 1, "hits" => 1}, {"number" => 5, "hits" => 5}])
      end

      it "starts with color on and both compact forms off" do
        opts = SimpleCov::CLI::Show.parse([])
        expect(opts).to include(no_color: false, uncovered_only: false, json: false, path: nil)
      end

      it "takes each flag when it is given" do
        opts = SimpleCov::CLI::Show.parse(%w[--input other.json --no-color --uncovered-only --json lib/a.rb])
        expect(opts).to eq(input: "other.json", no_color: true, uncovered_only: true, json: true, path: "lib/a.rb")
      end

      it "takes the first bare argument as the path" do
        expect(SimpleCov::CLI::Show.parse(%w[lib/a.rb lib/b.rb])[:path]).to eq("lib/a.rb")
      end
    end

    context "with a source list carrying something that is not a line" do
      before do
        entry["source"] = ["def call", 42]
        File.write(json_path, JSON.dump(payload))
      end

      it "errors" do
        expect(run("show", "--input", json_path, "lib/code.rb")).to eq(1)
      end

      it "reports it as no source at all" do
        run("show", "--input", json_path, "lib/code.rb")

        expect(stderr.string).to include("no source for lib/code.rb")
      end
    end

    context "with a source that is not a list of lines" do
      before do
        entry["source"] = "def call\nend\n"
        File.write(json_path, JSON.dump(payload))
      end

      it "errors" do
        expect(run("show", "--input", json_path, "lib/code.rb")).to eq(1)
      end

      it "reports it as no source at all" do
        run("show", "--input", json_path, "lib/code.rb")

        expect(stderr.string).to include("no source for lib/code.rb")
      end
    end
  end

  describe SimpleCov::CLI::Show::Annotator, mutant_expression: "SimpleCov::CLI::Show::Annotator*" do
    let(:annotator) { described_class }
    let(:out) { StringIO.new }

    describe "#count_width" do
      it "measures the widest hit count" do
        expect(annotator.count_width({"lines" => [1, 100, 5]})).to eq(3)
      end

      it "ignores the lines carrying no count at all" do
        expect(annotator.count_width({"lines" => [nil, 7, nil]})).to eq(1)
      end

      it "falls back to a single column when nothing is counted" do
        expect(annotator.count_width({"lines" => [nil, nil]})).to eq(1)
      end

      it "falls back to a single column for no lines at all" do
        expect(annotator.count_width({"lines" => []})).to eq(1)
      end
    end

    describe "#missed_line_of" do
      it "reads a zero-hit item's reported line" do
        expect(annotator.missed_line_of({"report_line" => 4, "coverage" => 0})).to eq(4)
      end

      it "prefers the reported line to the starting one" do
        expect(annotator.missed_line_of({"report_line" => 4, "start_line" => 9, "coverage" => 0})).to eq(4)
      end

      it "falls back to the starting line" do
        expect(annotator.missed_line_of({"start_line" => 9, "coverage" => 0})).to eq(9)
      end

      it "passes over an item that was hit" do
        expect(annotator.missed_line_of({"report_line" => 4, "coverage" => 1})).to be_nil
      end

      [
        ["a count that is nothing", {"report_line" => 4, "coverage" => nil}],
        ["a count that is a string", {"report_line" => 4, "coverage" => "0"}],
        ["no count at all", {"report_line" => 4}],
        ["a line that is a string", {"report_line" => "4", "coverage" => 0}],
        ["no line at all", {"coverage" => 0}],
        ["a string in place of the item", "junk"],
        ["nothing in place of the item", nil],
        ["a list in place of the item", [{"report_line" => 4, "coverage" => 0}]]
      ].each do |description, item|
        it "passes over an item with #{description}" do
          expect(annotator.missed_line_of(item)).to be_nil
        end
      end
    end

    describe "#each_missed" do
      it "yields the line of every missed item and no other" do
        items = [{"report_line" => 2, "coverage" => 0}, {"report_line" => 3, "coverage" => 1},
          {"report_line" => 5, "coverage" => 0}]

        expect { |probe| annotator.each_missed(items, &probe) }.to yield_successive_args(2, 5)
      end

      [["nothing", nil], ["a string", "junk"], ["an empty list", []]].each do |description, items|
        it "yields nothing for #{description} to walk" do
          expect { |probe| annotator.each_missed(items, &probe) }.not_to yield_control
        end
      end
    end

    describe "#missed_lines" do
      it "numbers the zero-hit lines from one" do
        expect(annotator.missed_lines({"lines" => [0, 1, 0, nil]})).to eq([1, 3])
      end

      it "passes over the lines that carry no count" do
        expect(annotator.missed_lines({"lines" => [nil, nil]})).to be_empty
      end

      it "passes over a zero that is no count" do
        expect(annotator.missed_lines({"lines" => [0.0]})).to be_empty
      end
    end

    describe "#call" do
      it "leaves the gutter blank past the end of the counts" do
        annotator.call(%w[one two], {"lines" => [1], "branches" => [], "methods" => []}, out, color: false)

        expect(out.string).to eq("1  1  one\n2     two\n")
      end

      it "paints the caret as well as the count" do
        annotator.call(%w[one], {"lines" => [0], "branches" => [], "methods" => []}, out, color: true)

        expect(out.string).to eq("1  \e[31m0\e[0m  one\n      \e[31m^ missed\e[0m\n")
      end
    end

    describe "#row" do
      def widths = {number: 2, count: 3}

      it "right-aligns the number and the count in their columns" do
        expect(annotator.row(7, 42, "code", widths, false)).to eq(" 7   42  code")
      end

      it "leaves the count column blank for a line that carries none" do
        expect(annotator.row(7, nil, "code", widths, false)).to eq(" 7       code")
      end

      it "leaves the column blank for a count that is no number" do
        expect(annotator.row(7, "3", "code", widths, false)).to eq(" 7       code")
      end

      it "trims a row whose source line is empty" do
        expect(annotator.row(7, nil, "", widths, false)).to eq(" 7")
      end

      it "paints a missed count red, after padding" do
        expect(annotator.row(7, 0, "code", widths, true)).to eq(" 7  \e[31m  0\e[0m  code")
      end

      it "paints a hit count green, after padding" do
        expect(annotator.row(7, 1, "code", widths, true)).to eq(" 7  \e[32m  1\e[0m  code")
      end

      it "leaves a blank count unpainted" do
        expect(annotator.row(7, nil, "code", widths, true)).to eq(" 7       code")
      end
    end

    describe "#emit" do
      def widths = {number: 2, count: 3}

      it "prints the row alone when nothing is missed on it" do
        annotator.emit(out, " 7   42  code", [], widths, false)

        expect(out.string).to eq(" 7   42  code\n")
      end

      it "points a caret at the source column under the row" do
        annotator.emit(out, " 7    0  code", ["missed"], widths, false)

        expect(out.string).to eq(" 7    0  code\n         ^ missed\n")
      end

      it "joins a line's labels on the one caret" do
        annotator.emit(out, " 7    0  code", ["missed", "branch missed"], widths, false)

        expect(out.string).to include("^ missed, branch missed\n")
      end

      it "paints the caret line red" do
        annotator.emit(out, " 7    0  code", ["missed"], widths, true)

        expect(out.string).to include("\e[31m^ missed\e[0m")
      end
    end
  end

  describe "uncovered subcommand", mutant_expression: "SimpleCov::CLI::Uncovered*" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-uncovered-spec-") }

    def json_path = File.join(tmp, "coverage.json")

    def unreadable_lines
      {"total_lines" => 4, "covered_lines" => 2, "lines_covered_percent" => 50.0, "lines" => "junk"}
    end

    def repeated_missed_branches
      {
        "total_branches" => 4, "covered_branches" => 0, "branches_covered_percent" => 0.0,
        "branches" => [{"report_line" => 7, "coverage" => 0}, {"report_line" => 2, "coverage" => 0},
          {"report_line" => 7, "coverage" => 0}]
      }
    end

    def rooted_misses
      {"total_lines" => 2, "covered_lines" => 0, "lines_covered_percent" => 0.0, "lines" => [0, 0]}
    end

    def fully_covered
      {"total_lines" => 10, "covered_lines" => 10, "lines_covered_percent" => 100.0}
    end

    def half_covered
      {"total_lines" => 10, "covered_lines" => 5, "lines_covered_percent" => 50.0}
    end

    def partial_branches
      {"total_branches" => 4, "covered_branches" => 1, "branches_covered_percent" => 25.0}
    end

    def write_coverage(entries)
      File.write(json_path, JSON.dump("coverage" => entries))
    end

    # Writes a report carrying one file's figures, the shape most of these
    # examples want.
    def write_entry(figures)
      write_coverage("/abs/lib/b.rb" => figures)
    end

    before do
      File.write(json_path, JSON.dump(
                              "coverage" => {
                                "/abs/lib/a.rb" => {
                                  "total_lines" => 10, "covered_lines" => 10, "lines_covered_percent" => 100.0
                                },
                                "/abs/lib/b.rb" => {
                                  "total_lines" => 10, "covered_lines" => 5, "lines_covered_percent" => 50.0
                                },
                                "/abs/lib/c.rb" => {
                                  "total_lines" => 10, "covered_lines" => 1, "lines_covered_percent" => 10.0,
                                  "lines" => [1, 0, 0, nil, 0, nil, nil, nil, nil, nil]
                                }
                              }
                            ))
    end

    after { FileUtils.remove_entry(tmp) }

    context "with no options beyond the input" do
      let(:lines) { stdout.string.lines.map(&:strip) }

      before { run("uncovered", "--input", json_path) }

      it "succeeds" do
        expect(run("uncovered", "--input", json_path)).to eq(0)
      end

      it "lists only the files below 100%" do
        expect(lines.size).to eq(2)
      end

      it "lists the worst first" do
        expect(lines.first).to include("/abs/lib/c.rb")
      end

      it "lists the rest after it" do
        expect(lines.last).to include("/abs/lib/b.rb")
      end
    end

    describe "--missing" do
      before do
        File.write(json_path, JSON.dump(
                                "coverage" => {
                                  "/abs/lib/b.rb" => {
                                    "total_lines" => 5, "covered_lines" => 1, "lines_covered_percent" => 20.0,
                                    "lines" => [1, 0, 0, 0, nil, 0],
                                    "total_branches" => 2, "covered_branches" => 1, "branches_covered_percent" => 50.0,
                                    "branches" => [{"report_line" => 2, "coverage" => 0},
                                      {"report_line" => 4, "coverage" => 3}],
                                    "total_methods" => 2, "covered_methods" => 1, "methods_covered_percent" => 50.0,
                                    "methods" => [{"start_line" => 9, "coverage" => 0},
                                      {"start_line" => 1, "coverage" => 2}]
                                  },
                                  "/abs/lib/stats_only.rb" => {
                                    "total_lines" => 2, "covered_lines" => 1, "lines_covered_percent" => 50.0
                                  }
                                }
                              ))
      end

      it "succeeds" do
        expect(run("uncovered", "--input", json_path, "--missing")).to eq(0)
      end

      it "appends the missed line ranges to each row" do
        run("uncovered", "--input", json_path, "--missing")

        expect(stdout.string).to include("/abs/lib/b.rb  missing 2-4,6")
      end

      it "appends nothing to a row it has no line data for" do
        run("uncovered", "--input", json_path, "--missing")

        expect(stdout.string.lines.find { |line| line.include?("stats_only") }).not_to include("missing")
      end

      it "follows the chosen criterion" do
        run("uncovered", "--input", json_path, "--missing", "--criterion", "branch")

        expect(stdout.string).to include("/abs/lib/b.rb  missing 2")
      end

      it "reports the lines missed methods start on" do
        run("uncovered", "--input", json_path, "--missing", "--criterion", "method")

        expect(stdout.string).to include("/abs/lib/b.rb  missing 9")
      end

      it "adds the missed lines to the JSON rows" do
        run("uncovered", "--input", json_path, "--missing", "--json")
        row = JSON.parse(stdout.string).find { |entry| entry["file"] == "/abs/lib/b.rb" }

        expect(row["missing"]).to eq([2, 3, 4, 6])
      end
    end

    describe "--annotate github" do
      before do
        File.write(json_path, JSON.dump(
                                "coverage" => {
                                  "/abs/lib/b.rb" => {
                                    "total_lines" => 5, "covered_lines" => 1, "lines_covered_percent" => 20.0,
                                    "lines" => [1, 0, 0, 0, nil, 0]
                                  },
                                  File.join(SimpleCov.root, "lib/rooted.rb") => {
                                    "total_lines" => 2, "covered_lines" => 1, "lines_covered_percent" => 50.0,
                                    "lines" => [1, 0]
                                  }
                                }
                              ))
      end

      let(:warnings) do
        <<~OUT
          ::warning file=/abs/lib/b.rb,line=2,endLine=4::Not covered by tests
          ::warning file=/abs/lib/b.rb,line=6,endLine=6::Not covered by tests
          ::warning file=lib/rooted.rb,line=2,endLine=2::Not covered by tests
        OUT
      end

      it "succeeds" do
        expect(run("uncovered", "--input", json_path, "--annotate", "github")).to eq(0)
      end

      it "emits one workflow warning per contiguous missed range" do
        run("uncovered", "--input", json_path, "--annotate", "github")

        expect(stdout.string).to eq(warnings)
      end

      it "succeeds when nothing is below the threshold" do
        expect(run("uncovered", "--input", json_path, "--annotate", "github", "--threshold", "0")).to eq(0)
      end

      it "stays silent when nothing is below the threshold" do
        run("uncovered", "--input", json_path, "--annotate", "github", "--threshold", "0")

        expect(stdout.string).to be_empty
      end

      it "rejects an unknown annotation format" do
        expect(run("uncovered", "--input", json_path, "--annotate", "gitlab")).to eq(1)
      end

      it "names the formats it knows" do
        run("uncovered", "--input", json_path, "--annotate", "gitlab")

        expect(stderr.string).to eq(%(simplecov uncovered: unknown --annotate "gitlab" (only github is supported)\n))
      end

      it "refuses to combine --annotate with --json" do
        expect(run("uncovered", "--input", json_path, "--annotate", "github", "--json")).to eq(1)
      end

      it "names the flag it cannot honor" do
        run("uncovered", "--input", json_path, "--annotate", "github", "--json")

        expect(stderr.string).to include("--json")
      end
    end

    it "counts a float covered and total as whole numbers" do
      write_entry("total_lines" => 4.0, "covered_lines" => 2.0, "lines_covered_percent" => 50.0)
      run!("uncovered", "--input", json_path)

      expect(stdout.string.strip).to eq("50.00%  2/4  /abs/lib/b.rb")
    end

    context "with float counts under --json" do
      let(:row) { JSON.parse(stdout.string).first }

      before do
        write_entry("total_lines" => 4.0, "covered_lines" => 2.0, "lines_covered_percent" => 50.25)
        run("uncovered", "--input", json_path, "--json")
      end

      it "succeeds" do
        expect(run("uncovered", "--input", json_path, "--json")).to eq(0)
      end

      it "carries the covered count whole" do
        expect(row["covered"]).to be(2)
      end

      it "carries the total whole" do
        expect(row["total"]).to be(4)
      end

      it "carries the percent as it stands" do
        expect(row["percent"]).to be(50.25)
      end
    end

    it "counts an absent percent as none" do
      write_entry("total_lines" => 4, "covered_lines" => 2)
      run!("uncovered", "--input", json_path)

      expect(stdout.string.strip).to eq("0.00%  2/4  /abs/lib/b.rb")
    end

    it "carries a whole-number percent as a fraction" do
      write_entry("total_lines" => 4, "covered_lines" => 2, "lines_covered_percent" => 50)
      run!("uncovered", "--input", json_path, "--json")

      expect(JSON.parse(stdout.string).first["percent"]).to be(50.0)
    end

    it "reads a count that carries trailing text as far as it is a number" do
      write_entry("total_lines" => "10 lines", "covered_lines" => "2 lines", "lines_covered_percent" => 20.0)
      run!("uncovered", "--input", json_path)

      expect(stdout.string.strip).to eq("20.00%  2/10  /abs/lib/b.rb")
    end

    it "lists the files below the threshold unless the missed lines are asked for" do
      run!("uncovered", "--input", json_path)

      expect(stdout.string).to include("/abs/lib/c.rb")
    end

    it "leaves the missed lines out of the rows unless they are asked for" do
      run!("uncovered", "--input", json_path)

      expect(stdout.string).not_to include("missing")
    end

    it "leaves the missed lines out of the JSON rows too" do
      run!("uncovered", "--input", json_path, "--json")

      expect(JSON.parse(stdout.string).map(&:keys).flatten.uniq)
        .to contain_exactly("file", "percent", "covered", "total")
    end

    it "keeps the worst files when --top caps the list" do
      run!("uncovered", "--input", json_path, "--top", "1")

      expect(stdout.string.strip).to end_with("/abs/lib/c.rb")
    end

    it "counts a string covered and total as whole numbers" do
      write_entry("total_lines" => "4", "covered_lines" => "2", "lines_covered_percent" => 50.0)
      run!("uncovered", "--input", json_path)

      expect(stdout.string.strip).to eq("50.00%  2/4  /abs/lib/b.rb")
    end

    it "passes over an entry that is not an object" do
      write_coverage("/abs/lib/b.rb" => "junk", "/abs/lib/c.rb" => [1, 2])
      run!("uncovered", "--input", json_path)

      expect(stdout.string).to eq("simplecov uncovered: nothing to report\n")
    end

    it "counts an absent covered figure as none" do
      write_entry("total_lines" => 4, "lines_covered_percent" => 0.0)
      run!("uncovered", "--input", json_path)

      expect(stdout.string.strip).to eq("0.00%  0/4  /abs/lib/b.rb")
    end

    it "reports no missed lines for line data that is not a list" do
      write_entry(unreadable_lines)
      run!("uncovered", "--input", json_path, "--missing")

      expect(stdout.string).not_to include("missing")
    end

    it "lists each missed line once, in order" do
      write_entry(repeated_missed_branches)
      run!("uncovered", "--input", json_path, "--missing", "--criterion", "branch")

      expect(stdout.string.strip).to end_with("missing 2,7")
    end

    it "reports no missed lines for a criterion the entry omits" do
      write_entry("total_branches" => 2, "covered_branches" => 0, "branches_covered_percent" => 0.0)
      run!("uncovered", "--input", json_path, "--missing", "--criterion", "branch")

      expect(stdout.string).not_to include("missing")
    end

    it "reports no missed lines for a method criterion the entry omits" do
      write_entry("total_methods" => 2, "covered_methods" => 0, "methods_covered_percent" => 0.0)
      run!("uncovered", "--input", json_path, "--missing", "--criterion", "method")

      expect(stdout.string).not_to include("missing")
    end

    it "carries an empty missing list for line data it cannot read" do
      write_entry(unreadable_lines)
      run!("uncovered", "--input", json_path, "--missing", "--json")

      expect(JSON.parse(stdout.string).first["missing"]).to eq([])
    end

    it "trims an unexpanded root off the annotated paths" do
      allow(SimpleCov).to receive(:root).and_return(File.join(tmp, "lib", ".."))
      write_coverage(File.join(tmp, "lib/b.rb") => rooted_misses)
      run!("uncovered", "--input", json_path, "--annotate", "github")

      expect(stdout.string).to eq("::warning file=lib/b.rb,line=1,endLine=2::Not covered by tests\n")
    end

    context "with a criterion it does not know" do
      it "errors" do
        expect(run("uncovered", "--input", json_path, "--criterion", "nope")).to eq(1)
      end

      it "names itself and the criteria it knows" do
        run("uncovered", "--input", json_path, "--criterion", "nope")

        expect(stderr.string)
          .to eq("simplecov uncovered: unknown --criterion :nope (expected line, branch, or method)\n")
      end
    end

    context "with an input it cannot find" do
      let(:missing) { File.join(tmp, "nope.json") }

      it "errors" do
        expect(run("uncovered", "--input", missing)).to eq(1)
      end

      it "names itself and the file" do
        run("uncovered", "--input", missing)

        expect(stderr.string).to eq("simplecov uncovered: #{missing} not found\n")
      end
    end

    it "honours --threshold" do
      run!("uncovered", "--input", json_path, "--threshold", "20")

      expect(stdout.string.lines.map(&:strip)).to all(include("/abs/lib/c.rb"))
    end

    it "honours --top to cap the list" do
      run!("uncovered", "--input", json_path, "--top", "1")

      expect(stdout.string.lines.size).to eq(1)
    end

    context "with a negative --top" do
      before { run("uncovered", "--input", json_path, "--top", "-1") }

      it "rejects it instead of raising" do
        expect(run("uncovered", "--input", json_path, "--top", "-1")).to eq(1)
      end

      it "says why" do
        expect(stderr.string).to include("invalid argument: --top must not be negative")
      end

      it "reports nothing" do
        expect(stdout.string).to be_empty
      end
    end

    it "reports nothing when every file is at 100%" do
      write_coverage("/abs/lib/a.rb" => {"total_lines" => 10, "covered_lines" => 10, "lines_covered_percent" => 100.0})
      run!("uncovered", "--input", json_path)

      expect(stdout.string).to include("nothing to report")
    end

    it "emits rows as a JSON array under --json" do
      run!("uncovered", "--input", json_path, "--json")

      expect(JSON.parse(stdout.string)).to be_an(Array)
    end

    it "carries the worst row's figures under --json" do
      run!("uncovered", "--input", json_path, "--json")

      expect(JSON.parse(stdout.string).first)
        .to include("file" => "/abs/lib/c.rb", "percent" => 10.0, "covered" => 1, "total" => 10)
    end

    it "carries the rest of the rows' figures too" do
      run!("uncovered", "--input", json_path, "--json")

      expect(JSON.parse(stdout.string).last)
        .to include("file" => "/abs/lib/b.rb", "percent" => 50.0, "covered" => 5, "total" => 10)
    end

    it "emits an empty JSON array when nothing is uncovered" do
      write_coverage("/abs/lib/a.rb" => fully_covered)
      run!("uncovered", "--input", json_path, "--json")

      expect(JSON.parse(stdout.string)).to eq([])
    end

    it "names the file whose chosen --criterion falls short" do
      write_coverage("/abs/lib/a.rb" => fully_covered.merge(partial_branches))
      run!("uncovered", "--input", json_path, "--criterion", "branch")

      expect(stdout.string).to include("/abs/lib/a.rb")
    end

    it "ranks it by the chosen --criterion" do
      write_coverage("/abs/lib/a.rb" => fully_covered.merge(partial_branches))
      run!("uncovered", "--input", json_path, "--criterion", "branch")

      expect(stdout.string).to include("25.00%")
    end

    it "rejects an unknown --criterion" do
      exited!(1, run("uncovered", "--input", json_path, "--criterion", "bogus"))

      expect(stderr.string).to include("unknown --criterion")
    end

    context "with colorization" do
      it "colorizes the worst listed percentage when Color.enabled? is true" do
        allow(SimpleCov::Color).to receive(:enabled?).and_return(true)
        run!("uncovered", "--input", json_path)

        expect(stdout.string).to match(/\e\[31m\s+10\.00%\e\[0m/)
      end

      it "colorizes the rest of them too" do
        allow(SimpleCov::Color).to receive(:enabled?).and_return(true)
        run!("uncovered", "--input", json_path)

        expect(stdout.string).to match(/\e\[31m\s+50\.00%\e\[0m/)
      end

      it_behaves_like "a --no-color subcommand" do
        let(:no_color_argv) { ["uncovered", "--input", json_path, "--no-color"] }
      end
    end

    it "skips coverage entries without a positive total_lines count" do
      write_coverage("/abs/lib/empty.rb" => {"total_lines" => 0}, "/abs/lib/a.rb" => half_covered)
      run!("uncovered", "--input", json_path)

      expect(stdout.string).not_to include("empty.rb")
    end

    it "keeps the entries that carry one" do
      write_coverage("/abs/lib/empty.rb" => {"total_lines" => 0}, "/abs/lib/a.rb" => half_covered)
      run!("uncovered", "--input", json_path)

      expect(stdout.string).to include("a.rb")
    end

    it "errors when the input file is missing" do
      exited!(1, run("uncovered", "--input", "/no/such.json"))

      expect(stderr.string).to include("not found")
    end
  end

  describe "merge subcommand", mutant_expression: "SimpleCov::CLI::Merge*" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-merge-spec-") }
    let(:shared_command_name_warning) do
      "simplecov merge: warning \u2014 command_name \"RSpec\" appears in 2 input files " \
        "(#{a}, #{b}); entries will be merged\n"
    end

    def a = File.join(tmp, "a.json")

    def b = File.join(tmp, "b.json")

    def out = File.join(tmp, "merged.json")

    def file = File.expand_path("spec/fixtures/sample.rb", SimpleCov.root)

    def c = File.join(tmp, "c.json")

    after { FileUtils.remove_entry(tmp) }

    def write_resultset(path, command_name, file_path, lines, outdated: false)
      stamp = outdated ? Time.now.to_i - 100_000 : Time.now.to_i
      entry = {"coverage" => {file_path => {"lines" => lines}}, "timestamp" => stamp}
      File.write(path, JSON.dump(command_name => entry))
    end

    it "hands back the merger" do
      allow(SimpleCov::CLI::Merge).to receive(:require)

      expect(SimpleCov::CLI::Merge.send(:result_merger)).to be(SimpleCov::ResultMerger)
    end

    it "loads the full library on the way to it" do
      allow(SimpleCov::CLI::Merge).to receive(:require)
      SimpleCov::CLI::Merge.send(:result_merger)

      expect(SimpleCov::CLI::Merge).to have_received(:require).with("simplecov")
    end

    it "ignores the merge timeout unless told to honour it" do
      write_resultset(a, "worker_1", file, [1, 0, nil], outdated: true)

      run!("merge", "--output", out, a)

      expect(JSON.parse(File.read(out)).keys).to eq(["worker_1"])
    end

    it "quotes what the JSON parser said about an unparseable input" do
      File.write(a, "{")

      exited!(1, run("merge", "--output", out, a))

      expect(stderr.string).to match(/\Asimplecov merge: input file .* isn't valid JSON \(.+\)\n\z/)
    end

    it "leaves no empty parenthesis where the parser said nothing" do
      File.write(a, "{")

      exited!(1, run("merge", "--output", out, a))

      expect(stderr.string).not_to include("()")
    end

    it "warns about a duplicate that follows a command name of its own" do
      write_resultset(a, "solo", file, [1, 0, nil])
      write_resultset(b, "shared", file, [0, 1, nil])
      write_resultset(c, "shared", file, [1, 1, nil])

      run!("merge", "--output", out, a, b, c)

      expect(stderr.string).to include(%(command_name "shared" appears in 2 input files))
    end

    context "when a process that has not loaded the library merges" do
      let(:standalone) do
        write_resultset(a, "worker_1", file, [1, 0, nil])
        exe = File.expand_path("../../exe/simplecov", __dir__)
        lib = File.expand_path("../../lib", __dir__)
        Open3.capture3(RbConfig.ruby, "-I", lib, exe, "merge", "--output", out, a)
      end

      it "exits cleanly" do
        expect(standalone.last.exitstatus).to eq(0), standalone[1]
      end

      it "loads the library it merges with" do
        expect(standalone.first).to include("wrote #{out}")
      end
    end

    it "stops at missing input files rather than going on" do
      exited!(1, run("merge", "--output", out))

      expect(stderr.string).to eq("simplecov merge: missing input files\n")
    end

    it "writes no output when it stops" do
      exited!(1, run("merge", "--output", out))

      expect(File.exist?(out)).to be false
    end

    it "errors when no input files are given" do
      exited!(1, run("merge"))

      expect(stderr.string).to include("missing input files")
    end

    context "with two resultsets" do
      let(:merged) do
        write_resultset(a, "worker_1", file, [1, 0, nil])
        write_resultset(b, "worker_2", file, [1, 1, nil])
        run!("merge", "--output", out, a, b)
        JSON.parse(File.read(out))
      end

      it "names both commands in the merged JSON" do
        expect(merged.keys.first).to include("worker_1").and include("worker_2")
      end

      it "sums their coverage" do
        expect(merged.values.first.dig("coverage", file, "lines")).to eq([2, 1, nil])
      end
    end

    it "surfaces a specific JSON parse error for an unparseable input" do
      bad = File.join(tmp, "bad.json")
      File.write(bad, "")
      exited!(1, run("merge", "--output", out, bad))

      expect(stderr.string).to include("isn't valid JSON").and include("bad.json")
    end

    it "surfaces a specific error when an input is structurally empty" do
      empty = File.join(tmp, "empty.json")
      File.write(empty, "{}")
      exited!(1, run("merge", "--output", out, empty))

      expect(stderr.string).to include("no resultset entries").and include("empty.json")
    end

    it "surfaces a specific error when an input file doesn't exist" do
      exited!(1, run("merge", "--output", out, File.join(tmp, "nope.json")))

      expect(stderr.string).to include("not found").and include("nope.json")
    end

    it "surfaces a specific error when an input path is not a readable file" do
      exited!(1, run("merge", "--output", out, tmp))

      expect(stderr.string).to match(/\Asimplecov merge: input file "\S.*" cannot be read \(\S.*\)\n\z/)
    end

    context "with a multi-line read error" do
      let(:wordy) { Errno::EACCES.new("first line\nsecond line") }

      before do
        allow(File).to receive(:read).and_raise(wordy)
        exited!(1, run("merge", "--output", out, a))
      end

      it "reports it in one line" do
        expect(stderr.string.lines.size).to eq(1)
      end

      it "reports only its first line" do
        expect(stderr.string).to end_with("cannot be read (#{wordy.message.lines.first.rstrip})\n")
      end
    end

    it "reports an unreadable input whose error says nothing" do
      silent = Class.new(Errno::EACCES) { def message = "" }
      allow(File).to receive(:read).and_raise(silent.new)

      exited!(1, run("merge", "--output", out, a))

      expect(stderr.string).to end_with("cannot be read ()\n")
    end

    it "errors when --honor-timeout expires every input's entries" do
      File.write(a, JSON.dump("worker_1" => {"coverage" => {file => {"lines" => [1]}},
                                             "timestamp" => Time.now.to_i - 86_400}))
      exited!(1, run("merge", "--output", out, "--honor-timeout", a))

      expect(stderr.string).to include("no mergeable results")
    end

    it "warns when two input files share a command_name" do
      write_resultset(a, "RSpec", file, [1, 0, nil])
      write_resultset(b, "RSpec", file, [0, 1, nil])

      run!("merge", "--output", out, a, b)

      expect(stderr.string).to eq(shared_command_name_warning)
    end

    it "writes to the project resultset when no output is named" do
      write_resultset(a, "worker_1", file, [1, 0, nil])
      allow(described_class).to receive(:default_resultset).and_return(out)

      run!("merge", a)

      expect(stdout.string).to eq("simplecov merge: wrote #{out}\n")
    end

    it "stays quiet when the command names are distinct" do
      write_resultset(a, "worker_1", file, [1, 0, nil])
      write_resultset(b, "worker_2", file, [1, 1, nil])

      run!("merge", "--output", out, a, b)

      expect(stderr.string).to be_empty
    end

    it "says it wrote the output when it did" do
      write_resultset(a, "worker_1", file, [1, 0, nil])

      run!("merge", "--output", out, a)

      expect(stdout.string).to eq("simplecov merge: wrote #{out}\n")
    end

    it "surfaces a specific error when an input is not an object" do
      File.write(a, JSON.dump([{"coverage" => {}}]))

      exited!(1, run("merge", "--output", out, a))

      expect(stderr.string).to eq(%(simplecov merge: input file #{a.inspect} has no resultset entries\n))
    end

    context "with --dry-run" do
      before do
        write_resultset(a, "worker_1", file, [1, 0, nil])
        run!("merge", "--output", out, "--dry-run", a)
      end

      it "doesn't write the output file" do
        expect(File.exist?(out)).to be false
      end

      it "says what it would have written" do
        expect(stdout.string).to eq("simplecov merge: would write #{out}\n")
      end
    end

    context "with --quiet" do
      before do
        write_resultset(a, "worker_1", file, [1, 0, nil])
        run!("merge", "--output", out, "--quiet", a)
      end

      it "silences the success status line" do
        expect(stdout.string).to be_empty
      end

      it "still writes the output file" do
        expect(File.exist?(out)).to be true
      end
    end

    it "accepts -q as the short alias for --quiet" do
      write_resultset(a, "worker_1", file, [1, 0, nil])

      run!("merge", "--output", out, "-q", a)

      expect(stdout.string).to be_empty
    end
  end

  describe "diff subcommand", mutant_expression: "SimpleCov::CLI::Diff*" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-diff-spec-") }
    let(:current) { File.join(tmp, "current.json") }
    let(:baseline) { File.join(tmp, "baseline.json") }

    def branchy
      {"covered_lines" => 80, "lines_covered_percent" => 80.0,
       "total_branches" => 20, "covered_branches" => 16, "branches_covered_percent" => 80.0}
    end

    def every_criterion
      {"covered_lines" => 80, "lines_covered_percent" => 80.0,
       "total_branches" => 10, "covered_branches" => 5, "branches_covered_percent" => 50.0,
       "total_methods" => 10, "covered_methods" => 4, "methods_covered_percent" => 40.0}
    end

    def added_and_removed_rows
      ["  -80.00% lines  lib/gone.rb  (removed)", "  + 60.00% lines  lib/new.rb  (new file)"]
    end

    def lines_that_rose = {"covered_lines" => 85, "lines_covered_percent" => 85.0}

    def every_colorized_criterion
      ["\e[32m+  5.00% lines\e[0m", "\e[32m+ 20.00% branches\e[0m", "\e[31m-10.00% methods\e[0m"]
    end

    def sub_epsilon_noise
      branchy.merge("covered_lines" => 85, "lines_covered_percent" => 85.0,
        "branches_covered_percent" => 80.0 - 1e-14)
    end

    def methodful
      {"covered_lines" => 80, "lines_covered_percent" => 80.0,
       "total_methods" => 20, "covered_methods" => 18, "methods_covered_percent" => 90.0}
    end

    def every_criterion_moved
      {"covered_lines" => 80, "lines_covered_percent" => 80.0,
       "total_branches" => 10, "covered_branches" => 7, "branches_covered_percent" => 70.0,
       "total_methods" => 10, "covered_methods" => 3, "methods_covered_percent" => 30.0}
    end

    after { FileUtils.remove_entry(tmp) }

    def write_coverage(path, files)
      File.write(path, JSON.dump("coverage" => files.transform_values do |entry|
        case entry
        when Hash
          {"total_lines" => 100, "covered_lines" => 0, "lines_covered_percent" => 0.0}.merge(entry)
        else
          {"total_lines" => 100, "covered_lines" => entry, "lines_covered_percent" => entry.to_f}
        end
      end))
    end

    context "with files that moved either way" do
      let(:lines) do
        write_coverage(baseline, "lib/a.rb" => 80, "lib/b.rb" => 50, "lib/c.rb" => 100)
        write_coverage(current, "lib/a.rb" => 85, "lib/b.rb" => 30, "lib/c.rb" => 100)
        run!("diff", "--input", current, baseline)
        stdout.string.lines.map(&:strip)
      end

      it "leaves the file that did not move out" do
        expect(lines.size).to eq(2)
      end

      it "lists the regression first" do
        expect(lines.first).to include("lib/b.rb").and match(/-\s*20\.00%/)
      end

      it "lists the improvement after it" do
        expect(lines.last).to include("lib/a.rb").and match(/\+\s*5\.00%/)
      end
    end

    it "treats new files as a 0%-baseline delta" do
      write_coverage(baseline, "lib/a.rb" => 80)
      write_coverage(current, "lib/a.rb" => 80, "lib/new.rb" => 60)

      run("diff", "--input", current, baseline)
      expect(stdout.string).to include("lib/new.rb").and match(/\+\s*60\.00%/)
    end

    it "exits 0 with a friendly message when nothing moved" do
      write_coverage(baseline, "lib/a.rb" => 80)
      write_coverage(current, "lib/a.rb" => 80)

      run!("diff", "--input", current, baseline)

      expect(stdout.string).to include("no per-file coverage changes")
    end

    it "exits non-zero on regression when --fail-on-drop is set" do
      write_coverage(baseline, "lib/a.rb" => 80)
      write_coverage(current, "lib/a.rb" => 70)

      expect(run("diff", "--input", current, "--fail-on-drop", baseline)).to eq(1)
    end

    it "does not fail on sub-epsilon float noise under --fail-on-drop" do
      write_coverage(baseline, "lib/a.rb" => branchy)
      write_coverage(current, "lib/a.rb" => sub_epsilon_noise)

      run!("diff", "--input", current, "--fail-on-drop", baseline)

      expect(stdout.string).to include("lib/a.rb").and match(/\+\s*5\.00%\s+lines/)
    end

    it "errors when the baseline argument is missing" do
      exited!(1, run("diff"))

      expect(stderr.string).to include("missing baseline argument")
    end

    context "with a negative threshold" do
      before do
        write_coverage(baseline, "lib/small.rb" => 80, "lib/big.rb" => 50)
        write_coverage(current, "lib/small.rb" => 83, "lib/big.rb" => 56)
        run!("diff", "--input", current, "--threshold", "-5", baseline)
      end

      it "reads it as the same distance as a positive one" do
        expect(stdout.string).to include("lib/big.rb")
      end

      it "still filters out the smaller move" do
        expect(stdout.string).not_to include("lib/small.rb")
      end
    end

    it "reads a file with nothing to cover as 0%, not as fully covered" do
      write_coverage(baseline, "lib/a.rb" => {"total_lines" => 0, "covered_lines" => 0})
      write_coverage(current, "lib/a.rb" => {"covered_lines" => 100, "lines_covered_percent" => 100.0})

      run!("diff", "--input", current, baseline)

      expect(stdout.string).to include("lib/a.rb").and match(/\+\s*100\.00%/)
    end

    it "renders a row as sign, width-aligned delta, criterion and file" do
      write_coverage(baseline, "lib/a.rb" => 80)
      write_coverage(current, "lib/a.rb" => 85)

      run("diff", "--input", current, baseline)
      expect(stdout.string).to eq("  +  5.00% lines  lib/a.rb\n")
    end

    it "renders every criterion that moved, and only those" do
      write_coverage(baseline, "lib/a.rb" => every_criterion)
      write_coverage(current, "lib/a.rb" => every_criterion_moved)

      run("diff", "--input", current, baseline)
      expect(stdout.string).to eq("    0.00% lines  + 20.00% branches  -10.00% methods  lib/a.rb\n")
    end

    it "marks an added file and a removed one by name" do
      write_coverage(baseline, "lib/gone.rb" => 80)
      write_coverage(current, "lib/new.rb" => 60)
      run!("diff", "--input", current, baseline)

      expect(stdout.string.lines.map(&:chomp)).to match_array(added_and_removed_rows)
    end

    it "lists a sub-one-percent move under the default threshold" do
      write_coverage(baseline, "lib/a.rb" => {"covered_lines" => 80, "lines_covered_percent" => 80.0})
      write_coverage(current, "lib/a.rb" => {"covered_lines" => 80, "lines_covered_percent" => 80.5})

      run("diff", "--input", current, baseline)
      expect(stdout.string).to include("lib/a.rb")
    end

    it "reads a non-object payload as 0%, whatever it is" do
      File.write(current, JSON.dump("coverage" => {"lib/a.rb" => [1, 2, 3]}))
      write_coverage(baseline, "lib/a.rb" => 80)

      run!("diff", "--input", current, baseline)

      expect(stdout.string).to include("lib/a.rb").and include("-80.00%")
    end

    it "reads the baseline from the first positional argument" do
      write_coverage(baseline, "lib/a.rb" => 80)
      write_coverage(File.join(tmp, "other.json"), "lib/a.rb" => 10)
      write_coverage(current, "lib/a.rb" => 85)
      run!("diff", "--input", current, baseline, File.join(tmp, "other.json"))

      expect(stdout.string).to include("+  5.00%")
    end

    it "coerces a percent that arrived as a string" do
      write_coverage(baseline, "lib/a.rb" => {"covered_lines" => 80, "lines_covered_percent" => "80.0"})
      write_coverage(current, "lib/a.rb" => 85)

      run!("diff", "--input", current, baseline)

      expect(stdout.string).to include("+  5.00%")
    end

    it "colorizes every criterion it prints, not only the first" do
      allow(SimpleCov::Color).to receive(:enabled?).and_return(true)
      write_coverage(baseline, "lib/a.rb" => every_criterion)
      write_coverage(current, "lib/a.rb" => every_criterion_moved.merge(lines_that_rose))
      run!("diff", "--input", current, baseline)

      expect(stdout.string.scan(/\e\[3\dm[^\e]+\e\[0m/)).to eq(every_colorized_criterion)
    end

    it "reads a payload that counts lines but omits the percent as 0%" do
      File.write(baseline, JSON.dump("coverage" => {"lib/a.rb" => {"total_lines" => 100,
                                                                   "covered_lines" => 80}}))
      write_coverage(current, "lib/a.rb" => 85)

      run!("diff", "--input", current, baseline)

      expect(stdout.string).to include("+ 85.00%")
    end

    it "names the subcommand in the error when the baseline cannot be read" do
      write_coverage(current, "lib/a.rb" => 80)

      run("diff", "--input", current, baseline)
      expect(stderr.string).to start_with("simplecov diff:")
    end

    it "errors when the baseline file is missing" do
      write_coverage(current, "lib/a.rb" => 80)

      exited!(1, run("diff", "--input", current, baseline))

      expect(stderr.string).to include(baseline).and include("not found")
    end

    it "errors when the current input file is missing" do
      write_coverage(baseline, "lib/a.rb" => 80)

      exited!(1, run("diff", "--input", current, baseline))

      expect(stderr.string).to include(current).and include("not found")
    end

    it "fails on a branch coverage drop when --fail-on-drop is set" do
      write_coverage(baseline, "lib/a.rb" => branchy)
      write_coverage(current,
        "lib/a.rb" => branchy.merge("covered_branches" => 10, "branches_covered_percent" => 50.0))

      exited!(1, run("diff", "--input", current, "--fail-on-drop", baseline))

      expect(stdout.string).to include("lib/a.rb").and match(/-\s*30\.00%\s+branches/)
    end

    it "fails on a method coverage drop when --fail-on-drop is set" do
      write_coverage(baseline, "lib/a.rb" => methodful)
      write_coverage(current,
        "lib/a.rb" => methodful.merge("covered_methods" => 15, "methods_covered_percent" => 75.0))

      exited!(1, run("diff", "--input", current, "--fail-on-drop", baseline))

      expect(stdout.string).to include("lib/a.rb").and match(/-\s*15\.00%\s+methods/)
    end

    it "leaves a criterion out when its totals are zero, however its percent reads" do
      write_coverage(baseline, "lib/a.rb" => zero_total_branches(40.0))
      write_coverage(current, "lib/a.rb" => zero_total_branches(90.0))

      run!("diff", "--input", current, baseline)

      expect(stdout.string).not_to include("branches")
    end

    # A report whose branch percent survived the branches it was computed from.
    def zero_total_branches(percent)
      {"covered_lines" => 80, "lines_covered_percent" => 80.0,
       "total_branches" => 0, "covered_branches" => 0, "branches_covered_percent" => percent}
    end

    it "tags new files with (new file)" do
      write_coverage(baseline, "lib/gone.rb" => 95)
      write_coverage(current, "lib/new.rb" => 60)

      run!("diff", "--input", current, baseline)

      expect(stdout.string).to include("lib/new.rb").and include("(new file)")
    end

    it "tags removed files with (removed)" do
      write_coverage(baseline, "lib/gone.rb" => 95)
      write_coverage(current, "lib/new.rb" => 60)

      run!("diff", "--input", current, baseline)

      expect(stdout.string).to include("lib/gone.rb").and include("(removed)")
    end

    it "normalizes leading slashes so pre-`project_filename` baselines diff cleanly" do
      write_coverage(baseline, "/lib/foo.rb" => 80)
      write_coverage(current, "lib/foo.rb" => 80)

      run!("diff", "--input", current, baseline)

      expect(stdout.string).to include("no per-file coverage changes")
    end

    context "with --json" do
      let(:payload) do
        write_coverage(baseline, "lib/a.rb" => 80)
        write_coverage(current, "lib/a.rb" => 70)
        run!("diff", "--input", current, "--json", baseline)
        JSON.parse(stdout.string)
      end

      it "emits an array" do
        expect(payload).to be_an(Array)
      end

      it "carries each file's delta" do
        expect(payload.first).to include("file" => "lib/a.rb", "status" => "changed", "line_delta" => -10.0)
      end
    end

    context "with --threshold" do
      before do
        write_coverage(baseline, "lib/a.rb" => 80, "lib/b.rb" => 80)
        write_coverage(current, "lib/a.rb" => 75, "lib/b.rb" => 60)
        run!("diff", "--input", current, "--threshold", "10", baseline)
      end

      it "keeps the file that moved past it" do
        expect(stdout.string).to include("lib/b.rb")
      end

      it "filters out the small-delta noise" do
        expect(stdout.string).not_to include("lib/a.rb")
      end
    end

    it "includes a file whose delta is exactly the threshold" do
      write_coverage(baseline, "lib/a.rb" => 80)
      write_coverage(current, "lib/a.rb" => 70)

      run!("diff", "--input", current, "--threshold", "10", baseline)

      expect(stdout.string).to include("lib/a.rb")
    end

    it "does not fail on a deleted file under --fail-on-drop" do
      write_coverage(baseline, "lib/a.rb" => 80, "lib/gone.rb" => 100)
      write_coverage(current, "lib/a.rb" => 80)

      run!("diff", "--input", current, "--fail-on-drop", baseline)

      expect(stdout.string).to include("(removed)")
    end

    context "with colorization" do
      it "colorizes regressions red and improvements green when Color.enabled? is true" do
        allow(SimpleCov::Color).to receive(:enabled?).and_return(true)
        write_coverage(baseline, "lib/a.rb" => 80, "lib/b.rb" => 50)
        write_coverage(current, "lib/a.rb" => 85, "lib/b.rb" => 30)

        run!("diff", "--input", current, baseline)

        expect(stdout.string).to match(/\e\[31m-\s*20\.00% lines\e\[0m/).and match(/\e\[32m\+\s*5\.00% lines\e\[0m/)
      end

      it_behaves_like "a --no-color subcommand" do
        before do
          write_coverage(baseline, "lib/a.rb" => 80)
          write_coverage(current, "lib/a.rb" => 70)
        end

        let(:no_color_argv) { ["diff", "--input", current, "--no-color", baseline] }
      end
    end
  end

  describe "ratchet subcommand", mutant_expression: "SimpleCov::CLI::Ratchet*" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-ratchet-spec-") }
    let(:ratcheted_summary) do
      {
        "written" => true, "path" => baseline_path,
        "tightened" => ["lib/improved.rb"], "pruned" => ["lib/deleted.rb"],
        "regressed" => ["lib/regressed.rb"], "unchanged" => []
      }
    end
    let(:two_files_at_ninety) do
      <<~YAML
        lib/one.rb:
          lines:
            percent: 90.0
            missed: 0
        lib/two.rb:
          lines:
            percent: 90.0
            missed: 0
      YAML
    end
    let(:generated_pass) do
      {
        "written" => true, "path" => baseline_path, "generated" => true, "files" => 1,
        "tightened" => [], "pruned" => [], "regressed" => [], "unchanged" => []
      }
    end

    def input = File.join(tmp, "coverage.json")

    def baseline_path = File.join(tmp, ".simplecov_baseline.yml")

    after { FileUtils.remove_entry(tmp) }

    def write_report(files)
      File.write(input, JSON.dump("coverage" => files.transform_values { |entry| report_row(entry) }))
    end

    def report_row(entry)
      row = {
        "lines_covered_percent" => entry.fetch(:percent), "covered_lines" => 10,
        "missed_lines" => entry.fetch(:missed), "total_lines" => 10 + entry.fetch(:missed)
      }
      if entry[:branch_percent]
        row.merge!("branches_covered_percent" => entry.fetch(:branch_percent), "covered_branches" => 1,
          "missed_branches" => entry.fetch(:branch_missed), "total_branches" => 4)
      end
      row
    end

    def read_baseline
      SimpleCov::Baseline.read_if_exists(baseline_path)
    end

    it "loads the full library before touching Baseline and the dotfile default" do
      allow(SimpleCov::CLI::Ratchet).to receive(:require)
      write_report("lib/foo.rb" => {percent: 41.2, missed: 137})

      run("ratchet", "--input", input, "--baseline", baseline_path, "--dry-run", "--quiet")

      expect(SimpleCov::CLI::Ratchet).to have_received(:require).with("simplecov")
    end

    it "reports a generated pass as JSON" do
      write_report("lib/foo.rb" => {percent: 41.2, missed: 137})

      run!("ratchet", "--input", input, "--baseline", baseline_path, "--json")

      expect(JSON.parse(stdout.string)).to eq(generated_pass)
    end

    context "with --dry-run" do
      before do
        write_report("lib/foo.rb" => {percent: 41.2, missed: 137})
        run!("ratchet", "--input", input, "--baseline", baseline_path, "--json", "--dry-run")
      end

      it "says nothing was written" do
        expect(JSON.parse(stdout.string)).to include("written" => false)
      end

      it "writes nothing" do
        expect(File).not_to exist(baseline_path)
      end
    end

    it "reports a ratcheted pass as JSON, saying it generated nothing" do
      write_report("lib/foo.rb" => {percent: 41.2, missed: 137})
      run!("ratchet", "--input", input, "--baseline", baseline_path)
      stdout.truncate(stdout.rewind)

      run!("ratchet", "--input", input, "--baseline", baseline_path, "--json")

      expect(JSON.parse(stdout.string)).to include("generated" => false, "files" => 1)
    end

    it "names itself when the report cannot be read" do
      exited!(1, run("ratchet", "--input", File.join(tmp, "absent.json"), "--baseline", baseline_path))

      expect(stderr.string).to eq("simplecov ratchet: #{File.join(tmp, "absent.json")} not found\n")
    end

    it "reports a baseline it cannot make sense of" do
      write_report("lib/foo.rb" => {percent: 41.2, missed: 137})
      File.write(baseline_path, "not: [a, baseline\n")

      exited!(1, run("ratchet", "--input", input, "--baseline", baseline_path))

      expect(stderr.string).to start_with("simplecov ratchet:")
    end

    describe "which rows can become a floor" do
      it "takes a row that carries both a percent and a count" do
        expect(described_class::Ratchet.usable?(41.2, 137)).to be(true)
      end

      it "refuses a row whose percent is not a number" do
        expect(described_class::Ratchet.usable?("41.2", 137)).to be(false)
      end

      it "refuses a row with no count beside the percent" do
        expect(described_class::Ratchet.usable?(41.2, nil)).to be(false)
      end

      it "refuses a count that is not a whole number" do
        expect(described_class::Ratchet.usable?(41.2, 137.5)).to be(false)
      end
    end

    describe "the line it prints" do
      before { write_report("lib/foo.rb" => {percent: 41.2, missed: 137}) }

      it "counts one generated file in the singular" do
        run("ratchet", "--input", input, "--baseline", baseline_path)
        expect(stdout.string).to eq("simplecov ratchet: wrote #{baseline_path} (1 file)\n")
      end

      it "counts several generated files in the plural" do
        write_report("lib/foo.rb" => {percent: 41.2, missed: 137}, "lib/bar.rb" => {percent: 50.0, missed: 5})

        run("ratchet", "--input", input, "--baseline", baseline_path)
        expect(stdout.string).to eq("simplecov ratchet: wrote #{baseline_path} (2 files)\n")
      end

      it "says it would write under --dry-run" do
        run("ratchet", "--input", input, "--baseline", baseline_path, "--dry-run")
        expect(stdout.string).to start_with("simplecov ratchet: would write #{baseline_path} (")
      end

      it "counts what moved once a baseline is there" do
        run!("ratchet", "--input", input, "--baseline", baseline_path)
        stdout.truncate(stdout.rewind)
        write_report("lib/foo.rb" => {percent: 80.0, missed: 2})
        run!("ratchet", "--input", input, "--baseline", baseline_path)

        expect(stdout.string).to eq("simplecov ratchet: wrote #{baseline_path} (1 tightened, 0 pruned, 0 unchanged)\n")
      end
    end

    describe "files that slipped below their floor" do
      before do
        write_report("lib/foo.rb" => {percent: 80.0, missed: 2}, "lib/bar.rb" => {percent: 80.0, missed: 2})
        run("ratchet", "--input", input, "--baseline", baseline_path)
        stdout.truncate(stdout.rewind)
      end

      it "says nothing when every file held its floor" do
        run("ratchet", "--input", input, "--baseline", baseline_path)
        expect(stdout.string).not_to include("below")
      end

      it "names one in the singular" do
        write_report("lib/foo.rb" => {percent: 10.0, missed: 90}, "lib/bar.rb" => {percent: 80.0, missed: 2})

        run("ratchet", "--input", input, "--baseline", baseline_path)
        expect(stdout.string).to include("simplecov ratchet: 1 file below its floor, entries kept unchanged")
      end

      it "names several in the plural" do
        write_report("lib/foo.rb" => {percent: 10.0, missed: 90}, "lib/bar.rb" => {percent: 10.0, missed: 90})

        run("ratchet", "--input", input, "--baseline", baseline_path)
        expect(stdout.string).to include("simplecov ratchet: 2 files below their floors, entries kept unchanged")
      end
    end

    it "rounds a floor to the precision coverage is reported at" do
      write_report("lib/foo.rb" => {percent: 41.23456789, missed: 137})

      run("ratchet", "--input", input, "--baseline", baseline_path)
      expect(read_baseline.entries.fetch("lib/foo.rb").fetch(:line).percent)
        .to eq(SimpleCov.round_coverage(41.23456789))
    end

    it "refuses a stray positional argument, naming the first" do
      write_report("lib/foo.rb" => {percent: 41.2, missed: 137})

      exited!(1, run("ratchet", "--input", input, "--baseline", baseline_path, "stray", "another"))

      expect(stderr.string).to eq("simplecov ratchet: unexpected argument \"stray\"\n")
    end

    context "when no baseline exists" do
      let(:baseline) do
        write_report(
          "lib/foo.rb" => {percent: 41.2, missed: 137, branch_percent: 25.0, branch_missed: 3},
          "lib/bar.rb" => {percent: 100.0, missed: 0}
        )
        run!("ratchet", "--input", input, "--baseline", baseline_path)
        read_baseline
      end

      it "says what it wrote" do
        baseline

        expect(stdout.string).to include("wrote #{baseline_path}").and include("2 files")
      end

      it "generates a line floor from the report" do
        expect(baseline.floor_for("lib/foo.rb", :line)).to have_attributes(percent: 41.2, missed: 137)
      end

      it "generates a branch floor beside it" do
        expect(baseline.floor_for("lib/foo.rb", :branch)).to have_attributes(percent: 25.0, missed: 3)
      end

      it "generates a floor for every file the report carries" do
        expect(baseline.floor_for("lib/bar.rb", :line)).to have_attributes(percent: 100.0, missed: 0)
      end
    end

    context "with an existing baseline" do
      before do
        File.write(baseline_path, <<~YAML)
          lib/improved.rb:
            lines:
              percent: 40.0
              missed: 10
          lib/regressed.rb:
            lines:
              percent: 90.0
              missed: 2
          lib/deleted.rb:
            lines:
              percent: 50.0
              missed: 5
        YAML
        write_report(
          "lib/improved.rb" => {percent: 75.0, missed: 4},
          "lib/regressed.rb" => {percent: 80.0, missed: 6},
          "lib/brand_new.rb" => {percent: 10.0, missed: 90}
        )
      end

      it "tightens an improved floor" do
        expect(ratcheted.floor_for("lib/improved.rb", :line)).to have_attributes(percent: 75.0, missed: 4)
      end

      it "keeps a regressed floor where it was" do
        expect(ratcheted.floor_for("lib/regressed.rb", :line)).to have_attributes(percent: 90.0, missed: 2)
      end

      it "prunes a deleted file" do
        expect(ratcheted.entry_for("lib/deleted.rb")).to be_nil
      end

      it "adds nothing for a file the baseline never carried" do
        expect(ratcheted.entry_for("lib/brand_new.rb")).to be_nil
      end

      def ratcheted
        run!("ratchet", "--input", input, "--baseline", baseline_path)
        read_baseline
      end

      it "summarizes what moved, including the files still below their floors" do
        run("ratchet", "--input", input, "--baseline", baseline_path)

        expect(stdout.string).to include("1 tightened, 1 pruned, 0 unchanged").and include("1 file below its floor")
      end

      it "prints what it would write under --dry-run" do
        run!("ratchet", "--input", input, "--baseline", baseline_path, "--dry-run")

        expect(stdout.string).to include("would write")
      end

      it "writes nothing under --dry-run" do
        before_content = File.read(baseline_path)
        run!("ratchet", "--input", input, "--baseline", baseline_path, "--dry-run")

        expect(File.read(baseline_path)).to eq(before_content)
      end

      it "adds new files under --init" do
        expect(regenerated.entry_for("lib/brand_new.rb")).not_to be_nil
      end

      it "still prunes deleted ones under --init" do
        expect(regenerated.entry_for("lib/deleted.rb")).to be_nil
      end

      it "resets a regressed floor under --init" do
        expect(regenerated.floor_for("lib/regressed.rb", :line)).to have_attributes(percent: 80.0, missed: 6)
      end

      it "emits the summary as JSON under --json" do
        run!("ratchet", "--input", input, "--baseline", baseline_path, "--json")

        expect(JSON.parse(stdout.string)).to include(ratcheted_summary)
      end

      def regenerated
        run!("ratchet", "--input", input, "--baseline", baseline_path, "--init")
        read_baseline
      end
    end

    context "with a report row carrying no usable counts" do
      let(:baseline) do
        File.write(input, JSON.dump("coverage" => {
          "lib/counted.rb" => {"lines_covered_percent" => 80.0, "covered_lines" => 8,
                               "missed_lines" => 2, "total_lines" => 10},
          "lib/percent_only.rb" => {"lines_covered_percent" => 50.0}
        }))
        run!("ratchet", "--input", input, "--baseline", baseline_path)
        read_baseline
      end

      it "keeps the row that carries counts" do
        expect(baseline.entry_for("lib/counted.rb")).not_to be_nil
      end

      it "skips the one that does not" do
        expect(baseline.entry_for("lib/percent_only.rb")).to be_nil
      end
    end

    it "pluralizes the below-floor note" do
      File.write(baseline_path, two_files_at_ninety)
      write_report("lib/one.rb" => {percent: 50.0, missed: 5}, "lib/two.rb" => {percent: 50.0, missed: 5})
      run("ratchet", "--input", input, "--baseline", baseline_path)

      expect(stdout.string).to include("2 files below their floors")
    end

    it "rejects a stray positional argument" do
      exited!(1, run("ratchet", "stray"))

      expect(stderr.string).to include('unexpected argument "stray"')
    end

    it "errors on a malformed baseline file" do
      write_report("lib/foo.rb" => {percent: 41.2, missed: 137})
      File.write(baseline_path, "{")

      exited!(1, run("ratchet", "--input", input, "--baseline", baseline_path))

      expect(stderr.string).to start_with("simplecov ratchet:").and include("not valid YAML")
    end

    it "defaults the baseline path to .simplecov_baseline.yml in the working directory" do
      write_report("lib/foo.rb" => {percent: 41.2, missed: 137})
      Dir.chdir(tmp) { ok!(run("ratchet", "--input", input)) }

      expect(File).to exist(baseline_path)
    end

    context "with SimpleCov.baseline_file in a project .simplecov" do
      before do
        write_report("lib/foo.rb" => {percent: 41.2, missed: 137})
        File.write(File.join(tmp, ".simplecov"), %(SimpleCov.baseline_file "floors.yml"\n))
        Dir.chdir(tmp) { ok!(run("ratchet", "--input", input)) }
      end

      it "writes the baseline it names" do
        expect(File).to exist(File.join(tmp, "floors.yml"))
      end

      it "writes no default baseline beside it" do
        expect(File).not_to exist(baseline_path)
      end
    end
  end

  describe "history output", mutant_expression: "SimpleCov::CLI::History*" do
    let(:out) { StringIO.new }
    let(:scoped_rows) do
      [{"created_at" => "2026-08-01T00:00:00Z", "branch" => "main", "commit" => "abcdef1234",
        "percents" => {"line" => 50.0}},
        {"created_at" => "2026-08-02T00:00:00Z", "branch" => "feature-x", "commit" => "1234567890",
         "percents" => nil},
        {"created_at" => "2026-08-03T00:00:00Z", "branch" => nil, "commit" => nil,
         "percents" => {"line" => 75.0}}]
    end
    let(:entries) do
      [{"created_at" => "2026-08-01T00:00:00Z", "branch" => "main", "commit" => "abcdef1234",
        "totals" => {"line" => 90.0, "branch" => 80.0}, "files" => {"lib/a.rb" => {"line" => 50.0}}},
        {"created_at" => "2026-08-02T00:00:00Z", "branch" => "feature-x", "commit" => "1234567890",
         "totals" => {"line" => 95.0, "branch" => 70.0}, "files" => {}},
        {"created_at" => "2026-08-03T00:00:00Z", "branch" => nil, "commit" => nil,
         "totals" => {"line" => 100.0, "branch" => 70.0}, "files" => {"lib/a.rb" => {"line" => 75.0}}}]
    end

    def null_row = {"created_at" => nil, "branch" => nil, "commit" => nil, "percents" => nil}

    def totals_view
      [
        "Coverage history: coverage/.history.json (3 runs)",
        "",
        "  line    ▁▅█  90.0% → 100.0%  (+10.0)",
        "  branch  █▁▁  80.0% → 70.0%  (-10.0)",
        "",
        "  2026-08-01T00:00:00Z  main       abcdef1  line 90.0%  branch 80.0%",
        "  2026-08-02T00:00:00Z  feature-x  1234567  line 95.0%  branch 70.0%",
        "  2026-08-03T00:00:00Z  -          -        line 100.0%  branch 70.0%"
      ].join("\n").concat("\n")
    end

    def one_file_view
      [
        "Coverage history for lib/a.rb (3 runs)",
        "",
        "  line  ▁ █  50.0% → 75.0%  (+25.0)",
        "",
        "  2026-08-01T00:00:00Z  main       abcdef1  line 50.0%",
        "  2026-08-02T00:00:00Z  feature-x  1234567  -",
        "  2026-08-03T00:00:00Z  -          -        line 75.0%"
      ].join("\n").concat("\n")
    end

    def sparse_view
      [
        "Coverage history: x (3 runs)",
        "",
        "  line  ▄    90.0% → 90.0%  (+0.0)",
        "",
        "    -  -        line 90.0%",
        "    -  -        -",
        "    -  -        -"
      ].join("\n").concat("\n")
    end

    def renderer = SimpleCov::CLI::History::Output

    it "draws the totals view whole" do
      renderer.emit(out, {input: "coverage/.history.json", json: false, file: nil}, entries, color: false)

      expect(out.string).to eq(totals_view)
    end

    it "draws one file's trajectory whole" do
      renderer.emit(out, {input: "x", json: false, file: "lib/a.rb"}, entries, color: false)

      expect(out.string).to eq(one_file_view)
    end

    it "says so plainly when nothing has been recorded" do
      renderer.emit(out, {input: "coverage/.history.json", json: false, file: nil}, [], color: false)

      expect(out.string).to eq("simplecov history: no recorded runs in coverage/.history.json\n")
    end

    it "emits the entries verbatim as data" do
      renderer.emit(out, {input: "x", json: true, file: nil}, entries, color: false)

      expect(JSON.parse(out.string)).to eq(entries)
    end

    it "emits one file's rows when scoped" do
      renderer.emit(out, {input: "x", json: true, file: "lib/a.rb"}, entries, color: false)

      expect(JSON.parse(out.string)).to eq(scoped_rows)
    end

    {
      [1.0, 2.0, 3.0] => "▁▅█",
      [5.0, 5.0] => "▄▄",
      [1.0, nil, 3.0] => "▁ █",
      [nil, nil] => "  ",
      [] => "",
      [3.0, 5.0, 1.0, 4.0] => "▅█▁▆",
      [90, 95, 100] => "▁▅█",
      [1.5, 2.5] => "▁█"
    }.each do |series, drawn|
      it "draws #{series.inspect} scaled to its own range, gapping what it has no value for" do
        expect(renderer.sparkline(series)).to eq(drawn)
      end
    end

    {
      [90.0, 100.0] => "90.0% → 100.0%  (+10.0)",
      [100.0, 90.0] => "100.0% → 90.0%  (-10.0)",
      [nil, 90.0, 90.0, nil] => "90.0% → 90.0%  (+0.0)"
    }.each do |series, trend|
      it "reads #{series.inspect} as a signed trend between its first and last recorded values" do
        expect(renderer.trend(series, false)).to eq(trend)
      end
    end

    it "colours a drop red" do
      expect(renderer.trend([100.0, 90.0], true)).to include("\e[31m(-10.0)\e[0m")
    end

    it "colours a rise green" do
      expect(renderer.trend([90.0, 100.0], true)).to include("\e[32m(+10.0)\e[0m")
    end

    it "lists every criterion the history ever recorded, in order" do
      late = [{"totals" => {"branch" => 1.0}}, {"totals" => {"line" => 2.0, "method" => 3.0}}]

      expect(renderer.measured_criteria(late, ["totals"])).to eq(%w[line branch method])
    end

    ["junk", [90.0]].each do |totals|
      it "lists no criterion for totals recorded as #{totals.inspect}" do
        expect(renderer.measured_criteria([{"totals" => totals}], ["totals"])).to eq([])
      end
    end

    {1 => "1 run", 2 => "2 runs", 0 => "0 runs"}.each do |count, words|
      it "counts #{count} in words that agree with the number" do
        expect(renderer.pluralize(count, "run")).to eq(words)
      end
    end

    it "reads a number as a percent" do
      expect(renderer.numeric(1.5)).to eq(1.5)
    end

    ["1.5", nil].each do |value|
      it "reads #{value.inspect} as no percent at all" do
        expect(renderer.numeric(value)).to be_nil
      end
    end

    it "colors the deltas of the totals view when color is on" do
      renderer.emit(out, {input: "x", json: false, file: nil}, entries, color: true)

      expect(out.string).to include("90.0% → 100.0%  \e[32m(+10.0)\e[0m")
        .and include("80.0% → 70.0%  \e[31m(-10.0)\e[0m")
    end

    it "colors one file's delta too" do
      renderer.emit(out, {input: "x", json: false, file: "lib/a.rb"}, entries, color: true)

      expect(out.string).to include("50.0% → 75.0%  \e[32m(+25.0)\e[0m")
    end

    it "draws a run that recorded none of the row's fields" do
      sparse = [{"totals" => {"line" => 90.0}}, {"totals" => {"line" => "?", "branch" => "?"}}, {}]

      renderer.emit(out, {input: "x", json: false, file: nil}, sparse, color: false)

      expect(out.string).to eq(sparse_view)
    end

    it "answers null columns for a run that recorded none of them" do
      sparse = [{}, {"files" => {"lib/a.rb" => "junk"}}]

      renderer.emit(out, {input: "x", json: true, file: "lib/a.rb"}, sparse, color: false)

      expect(JSON.parse(out.string)).to eq(Array.new(2) { null_row })
    end

    it "pads the criterion labels to the widest of them" do
      renderer.emit_sparklines(out, entries, %w[branch line], false, ["totals"])

      expect(out.string).to eq(
        ["  branch  █▁▁  80.0% → 70.0%  (-10.0)",
          "  line    ▁▅█  90.0% → 100.0%  (+10.0)"].join("\n").concat("\n")
      )
    end

    it "rounds the delta to two decimals" do
      expect(renderer.trend([90.123456, 95.0], false)).to eq("90.123456% → 95.0%  (+4.88)")
    end
  end

  describe "history subcommand", mutant_expression: "SimpleCov::CLI::History*" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-history-spec-") }
    let(:input) { File.join(tmp, ".history.json") }
    let(:one_file_history) do
      [
        entry("2026-08-23T10:00:00Z", 90.0, files: {"lib/foo.rb" => {"line" => 50.0}}),
        entry("2026-08-24T10:00:00Z", 95.0),
        entry("2026-08-25T10:00:00Z", 96.0, files: {"lib/foo.rb" => {"line" => 60.0}})
      ]
    end
    let(:one_file_rows) do
      [
        {"created_at" => "2026-08-23T10:00:00Z", "branch" => "main",
         "commit" => "abc123def456", "percents" => {"line" => 50.0}},
        {"created_at" => "2026-08-24T10:00:00Z", "branch" => "main",
         "commit" => "abc123def456", "percents" => nil},
        {"created_at" => "2026-08-25T10:00:00Z", "branch" => "main",
         "commit" => "abc123def456", "percents" => {"line" => 60.0}}
      ]
    end

    after { FileUtils.remove_entry(tmp) }

    def entry(created_at, line, branch: "main", commit: "abc123def456", files: {})
      {"created_at" => created_at, "branch" => branch, "commit" => commit,
       "totals" => {"line" => line}, "groups" => {}, "files" => files}
    end

    def write_history(entries)
      File.write(input, JSON.dump("simplecov_history" => {"format_version" => 1, "entries" => entries}))
    end

    def run_history(*extra)
      run("history", "--input", input, *extra)
    end

    context "with a multi-line parse error" do
      before do
        File.write(input, "{\n  bad\n}")
        exited!(1, run_history)
      end

      it "reports it in one line" do
        expect(stderr.string.lines.size).to eq(1)
      end

      it "reports only its first line" do
        expect(stderr.string).to match(/\Asimplecov history: \S.* is not valid JSON \(\S.*\)\n\z/)
      end
    end

    it "trims a multi-line parse error down to its first line" do
      File.write(input, "{}")
      allow(JSON).to receive(:parse)
        .and_raise(JSON::ParserError.new("  unexpected token at 'bad'  \nand more\n"))

      exited!(1, run_history)

      expect(stderr.string).to eq("simplecov history: #{input} is not valid JSON (unexpected token at 'bad')\n")
    end

    it "carries no percents for an entry that has no files section" do
      write_history([{"created_at" => "2026-08-23T10:00:00Z", "totals" => {"line" => 90.0}},
        entry("2026-08-24T10:00:00Z", 95.0, files: {"lib/a.rb" => {"line" => 95.0}})])

      ok!(run_history("--json", "--file", "lib/a.rb"))

      percents = JSON.parse(stdout.string).map { |row| row["percents"] }
      expect(percents).to eq([nil, {"line" => 95.0}])
    end

    context "with three recorded runs" do
      before do
        write_history([
          entry("2026-08-23T10:00:00Z", 90.0),
          entry("2026-08-24T10:00:00Z", 95.0, branch: nil, commit: nil),
          entry("2026-08-25T10:00:00Z", 100.0)
        ])
        ok!(run_history("--no-color"))
      end

      it "heads the report with the file and the run count" do
        expect(stdout.string).to include("Coverage history: #{input} (3 runs)")
      end

      it "prints a sparkline per criterion" do
        expect(stdout.string).to match(/line\s+▁▅█\s+90\.0% → 100\.0%\s+\(\+10\.0\)/)
      end

      it "prints a row per run beneath it" do
        expect(stdout.string).to include("2026-08-23T10:00:00Z  main  abc123d  line 90.0%")
      end

      it "dashes the columns a run did not record" do
        expect(stdout.string).to include("2026-08-24T10:00:00Z  -     -        line 95.0%")
      end
    end

    it "renders a flat series at mid height rather than dividing by zero" do
      write_history([entry("2026-08-23T10:00:00Z", 90.0), entry("2026-08-24T10:00:00Z", 90.0)])

      run_history("--no-color")

      expect(stdout.string).to match(/line\s+▄▄\s+90\.0% → 90\.0%\s+\(\+0\.0\)/)
    end

    context "with entries missing some or all totals" do
      before do
        first = entry("2026-08-23T10:00:00Z", 90.0)
        first["totals"]["branch"] = 80.0
        second = entry("2026-08-24T10:00:00Z", 95.0)
        second["totals"]["branch"] = 85.0
        fourth = entry("2026-08-26T10:00:00Z", 97.0)
        fourth["totals"] = nil
        write_history([first, second, entry("2026-08-25T10:00:00Z", 96.0), fourth])
        ok!(run_history("--no-color"))
      end

      it "sparks the criterion only some of them measured" do
        expect(stdout.string).to match(/branch\s+▁█ {2}\s+80\.0% → 85\.0%\s+\(\+5\.0\)/)
      end

      it "rows every criterion a run measured" do
        expect(stdout.string).to include("line 90.0%  branch 80.0%")
      end

      it "rows a run that measured only one of them" do
        expect(stdout.string).to include("2026-08-25T10:00:00Z  main  abc123d  line 96.0%")
      end
    end

    it "signs a decline" do
      write_history([entry("2026-08-23T10:00:00Z", 95.0), entry("2026-08-24T10:00:00Z", 90.0)])
      ok!(run_history("--no-color"))

      expect(stdout.string).to match(/line\s+█▁\s+95\.0% → 90\.0%\s+\(-5\.0\)/)
    end

    it "counts a single run in the singular" do
      write_history([entry("2026-08-23T10:00:00Z", 95.0)])
      ok!(run_history("--no-color"))

      expect(stdout.string).to include("(1 run)")
    end

    context "with --file" do
      before do
        write_history([
          entry("2026-08-23T10:00:00Z", 90.0, files: {"lib/foo.rb" => {"line" => 50.0, "branch" => 25.0}}),
          entry("2026-08-24T10:00:00Z", 95.0),
          entry("2026-08-25T10:00:00Z", 100.0, files: {"lib/foo.rb" => {"line" => 100.0, "branch" => 75.0}})
        ])
        ok!(run_history("--file", "lib/foo.rb", "--no-color"))
      end

      it "heads the report with the file" do
        expect(stdout.string).to include("Coverage history for lib/foo.rb (3 runs)")
      end

      it "follows the file's line trajectory" do
        expect(stdout.string).to match(/line\s+▁ █\s+50\.0% → 100\.0%\s+\(\+50\.0\)/)
      end

      it "follows its branch trajectory beside it" do
        expect(stdout.string).to match(/branch\s+▁ █\s+25\.0% → 75\.0%\s+\(\+50\.0\)/)
      end

      it "rows the runs that recorded it" do
        expect(stdout.string).to include("2026-08-23T10:00:00Z  main  abc123d  line 50.0%  branch 25.0%")
      end

      it "gaps the runs that did not" do
        expect(stdout.string).to include("2026-08-24T10:00:00Z  main  abc123d  -")
      end
    end

    it "errors under --file for a file no entry recorded" do
      write_history([entry("2026-08-23T10:00:00Z", 90.0)])

      exited!(1, run_history("--file", "lib/nope.rb"))

      expect(stderr.string).to include("no recorded coverage for lib/nope.rb")
    end

    it "errors under --file for a file recorded as something other than percentages" do
      write_history([entry("2026-08-23T10:00:00Z", 90.0, files: {"lib/foo.rb" => "junk"})])

      exited!(1, run_history("--file", "lib/foo.rb"))

      expect(stderr.string).to eq("simplecov history: no recorded coverage for lib/foo.rb in #{input}\n")
    end

    it "emits the entries as JSON" do
      write_history([entry("2026-08-23T10:00:00Z", 90.0)])

      ok!(run_history("--json"))

      expect(JSON.parse(stdout.string).fetch(0).fetch("totals")).to eq("line" => 90.0)
    end

    it "narrows the JSON to one file's trajectory under --file" do
      write_history(one_file_history)
      ok!(run_history("--file", "lib/foo.rb", "--json"))

      expect(JSON.parse(stdout.string)).to eq(one_file_rows)
    end

    it "reports an empty history plainly" do
      write_history([])

      ok!(run_history)

      expect(stdout.string).to include("no recorded runs")
    end

    it "errors when the history file is missing" do
      exited!(1, run_history)

      expect(stderr.string).to include("simplecov history:").and include("not found")
    end

    it "says the history is recorded for you" do
      exited!(1, run_history)

      expect(stderr.string).to include("recorded automatically")
    end

    it "errors when the file is not a history" do
      File.write(input, JSON.dump("something" => "else"))

      exited!(1, run_history)

      expect(stderr.string).to eq("simplecov history: #{input} is not a SimpleCov history file\n")
    end

    context "with a file that is not JSON" do
      before do
        File.write(input, "{")
        exited!(1, run_history)
      end

      it "names the file and what was wrong with it" do
        expect(stderr.string).to start_with("simplecov history: #{input} is not valid JSON (")
      end

      it "says it in one line" do
        expect(stderr.string.lines.length).to eq(1)
      end
    end

    it "errors when the file is JSON but not an object" do
      File.write(input, "[]")

      exited!(1, run_history)

      expect(stderr.string).to eq("simplecov history: #{input} is not a SimpleCov history file\n")
    end

    it "errors when the envelope carries entries that are not a list" do
      File.write(input, JSON.dump("simplecov_history" => {"entries" => "junk"}))

      exited!(1, run_history)

      expect(stderr.string).to eq("simplecov history: #{input} is not a SimpleCov history file\n")
    end

    it "errors when the history has never been written, saying why" do
      missing = File.join(tmp, "absent.json")

      exited!(1, run("history", "--input", missing))

      expect(stderr.string).to eq("simplecov history: #{missing} not found " \
        "(the history is recorded automatically each time a suite reports)\n")
    end

    it "names a file the history never recorded, rather than drawing an empty line" do
      write_history([entry("2026-08-01T00:00:00Z", 90.0, files: {"lib/a.rb" => {"line" => 50.0}})])

      exited!(1, run_history("--file", "lib/missing.rb"))

      expect(stderr.string).to eq("simplecov history: no recorded coverage for lib/missing.rb in #{input}\n")
    end

    it "errors when the path cannot be read as a file" do
      exited!(1, run("history", "--input", tmp))

      expect(stderr.string).to match(/\Asimplecov history: #{Regexp.escape(tmp)} could not be read \(\S.*\)\n\z/)
    end

    it "rejects a stray positional argument" do
      exited!(1, run("history", "stray"))

      expect(stderr.string).to include('unexpected argument "stray"')
    end

    it "names the first of several stray arguments" do
      exited!(1, run("history", "one", "two"))

      expect(stderr.string).to eq(%(simplecov history: unexpected argument "one"\n))
    end

    context "with no input named" do
      before do
        allow(described_class).to receive(:coverage_dir).and_return(tmp)
        write_history([entry("2026-08-23T10:00:00Z", 90.0)])
      end

      it "defaults to the history beside the report" do
        expect(described_class::History.default_input).to eq(input)
      end

      it "reads it" do
        run!("history", "--no-color")

        expect(stdout.string).to include("Coverage history: #{input} (1 run)")
      end
    end

    it "prints an empty parser complaint as an empty note" do
      File.write(input, "{}")
      allow(JSON).to receive(:parse).and_raise(JSON::ParserError.new(""))

      exited!(1, run_history)

      expect(stderr.string).to eq("simplecov history: #{input} is not valid JSON ()\n")
    end

    it "reads past an entry that is not an object when looking for a file" do
      write_history(["junk"])

      exited!(1, run_history("--file", "lib/a.rb"))

      expect(stderr.string).to eq("simplecov history: no recorded coverage for lib/a.rb in #{input}\n")
    end

    it "answers that a file nothing recorded was not recorded" do
      expect(described_class::History.file_recorded?([], {file: "lib/a.rb", input: input}, stderr)).to be(false)
    end

    it "answers that no file at all is always recorded" do
      expect(described_class::History.file_recorded?([], {file: nil, input: input}, stderr)).to be(true)
    end

    context "with colorization" do
      it "colors the trend when Color.enabled? is true" do
        allow(SimpleCov::Color).to receive(:enabled?).and_return(true)
        write_history([entry("2026-08-23T10:00:00Z", 90.0), entry("2026-08-24T10:00:00Z", 95.0)])

        ok!(run_history)

        expect(stdout.string).to include("90.0% → 95.0%  \e[32m(+5.0)\e[0m")
      end

      it_behaves_like "a --no-color subcommand" do
        before { write_history([entry("2026-08-23T10:00:00Z", 90.0)]) }

        let(:no_color_argv) { ["history", "--input", input, "--no-color"] }
      end
    end
  end

  describe "dead-code subcommand", mutant_expression: "SimpleCov::CLI::DeadCode*" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-dead-code-spec-") }

    def whole_report
      <<~REPORT
        Production coverage: #{production_path} (window 2026-01-01T00:00:00Z to 2026-02-01T00:00:00Z)

        Dead code (not run in production, not covered by tests):
          lib/dead.rb:1 (entire file)

        Possibly dead (not run in production, covered only by tests):
          lib/possible.rb:1 (entire file)

        1 dead line, 1 possibly dead line
      REPORT
    end

    def empty_report
      <<~REPORT
        Production coverage: #{production_path} (window 2026-01-01T00:00:00Z to 2026-02-01T00:00:00Z)

        No dead code found.
      REPORT
    end

    def sorted_payload
      {
        "window" => {"started_at" => "2026-01-01T00:00:00Z", "updated_at" => "2026-02-01T00:00:00Z"},
        "dead" => [{"file" => "lib/apple.rb", "lines" => [1], "last_seen" => "2026-03-04T05:06:07Z"},
          {"file" => "lib/zebra.rb", "lines" => [1]}],
        "possibly_dead" => [], "untested_in_production" => []
      }
    end

    def absent = File.join(tmp, "absent.json")

    def input = File.join(tmp, "coverage.json")

    def production_path = File.join(tmp, "production.json")

    before do
      File.write(input, JSON.dump("coverage" => {
        "lib/mixed.rb" => {"lines" => [1, 0, nil, 2, 0]},
        "lib/tested_unused.rb" => {"lines" => [2, 1]},
        "lib/ignored.rb" => {"lines" => ["ignored", nil]}
      }))
      SimpleCov::Production::FileSink.new(path: production_path).store(
        "lib/mixed.rb" => [1, 5], "lib/prod_only.rb" => [3, 4]
      )
    end

    after { FileUtils.remove_entry(tmp) }

    def write_production(coverage:, last_seen: {}, started_at: "2026-01-01T00:00:00Z",
      updated_at: "2026-02-01T00:00:00Z")
      window = {"format_version" => 1, "coverage" => coverage, "last_seen" => last_seen}
      window["started_at"] = started_at if started_at
      window["updated_at"] = updated_at if updated_at
      File.write(production_path, JSON.dump("simplecov_production" => window))
    end

    describe "the shape of the printed report" do
      before do
        File.write(input, JSON.dump("coverage" => {"lib/dead.rb" => {"lines" => [0]},
                                                   "lib/possible.rb" => {"lines" => [1]}}))
        write_production(coverage: {})
      end

      it "prints each section under its heading, and counts them at the end" do
        ok!(run_dead_code)

        expect(stdout.string).to eq(whole_report)
      end

      it "prints neither heading nor blank line for a category with nothing in it" do
        File.write(input, JSON.dump("coverage" => {"lib/dead.rb" => {"lines" => [0]}}))

        ok!(run_dead_code)

        expect(stdout.string).not_to include("Possibly dead")
      end

      it "says so plainly when there is nothing to report" do
        File.write(input, JSON.dump("coverage" => {}))

        ok!(run_dead_code)

        expect(stdout.string).to eq(empty_report)
      end

      it "says so plainly when nothing untested is running in production" do
        File.write(input, JSON.dump("coverage" => {}))

        ok!(run_dead_code("--untested-in-production"))

        expect(stdout.string).to end_with("No untested production code found.\n")
      end
    end

    context "with more than one file in a report category" do
      let(:listed) do
        File.write(input, JSON.dump("coverage" => {"lib/zebra.rb" => {"lines" => [0]},
                                                   "lib/apple.rb" => {"lines" => [0]}}))
        ok!(run_dead_code)
        stdout.string.lines.grep(/\.rb:/).map(&:strip)
      end

      before { write_production(coverage: {}) }

      it "lists the first in a settled order" do
        expect(listed.first).to start_with("lib/apple.rb:")
      end

      it "lists the last after it" do
        expect(listed.last).to start_with("lib/zebra.rb:")
      end
    end

    describe "the window the production data spans" do
      before { File.write(input, JSON.dump("coverage" => {})) }

      it "names the window when the store recorded both ends of it" do
        write_production(coverage: {})
        run_dead_code
        expect(stdout.string).to start_with(
          "Production coverage: #{production_path} (window 2026-01-01T00:00:00Z to 2026-02-01T00:00:00Z)"
        )
      end

      it "names no window when only its start was recorded" do
        write_production(coverage: {}, updated_at: nil)
        run_dead_code
        expect(stdout.string).to start_with("Production coverage: #{production_path}\n")
      end

      it "names no window when only its end was recorded" do
        write_production(coverage: {}, started_at: nil)
        run_dead_code
        expect(stdout.string).to start_with("Production coverage: #{production_path}\n")
      end
    end

    describe "dating a file the store last saw" do
      before { File.write(input, JSON.dump("coverage" => {"lib/dead.rb" => {"lines" => [0]}})) }

      it "dates the row from the stamp the store kept" do
        write_production(coverage: {}, last_seen: {"lib/dead.rb" => "2026-03-04T05:06:07Z"})

        run_dead_code
        expect(stdout.string).to include("lib/dead.rb:1 (entire file, last run 2026-03-04)")
      end

      it "dates nothing from a stamp that is not one" do
        write_production(coverage: {}, last_seen: {"lib/dead.rb" => 20_260_304})

        run_dead_code
        expect(stdout.string).to include("lib/dead.rb:1 (entire file)")
      end

      it "carries the whole stamp into JSON, and omits it when there is none" do
        write_production(coverage: {}, last_seen: {"lib/dead.rb" => 20_260_304})

        run_dead_code("--json")
        expect(JSON.parse(stdout.string).fetch("dead").first).to eq("file" => "lib/dead.rb", "lines" => [1])
      end
    end

    describe "the JSON payload" do
      it "carries the window and every category, each in a settled order" do
        File.write(input, JSON.dump("coverage" => {"lib/zebra.rb" => {"lines" => [0]},
                                                   "lib/apple.rb" => {"lines" => [0]}}))
        write_production(coverage: {}, last_seen: {"lib/apple.rb" => "2026-03-04T05:06:07Z"})

        ok!(run_dead_code("--json"))

        expect(JSON.parse(stdout.string)).to eq(sorted_payload)
      end

      it "carries a window the store never recorded as empty" do
        File.write(input, JSON.dump("coverage" => {}))
        write_production(coverage: {}, started_at: nil, updated_at: nil)

        run_dead_code("--json")
        expect(JSON.parse(stdout.string).fetch("window")).to eq("started_at" => nil, "updated_at" => nil)
      end
    end

    describe "reading a report that is not shaped like one" do
      it "skips a file whose lines are not a list" do
        File.write(input, JSON.dump("coverage" => {"lib/odd.rb" => {"lines" => "0,1,0"}}))

        ok!(run_dead_code)

        expect(stdout.string).to include("No dead code found.")
      end

      it "does not call a file with no relevant lines entirely dead" do
        File.write(input, JSON.dump("coverage" => {"lib/blank.rb" => {"lines" => [nil, nil]}}))

        ok!(run_dead_code)

        expect(stdout.string).not_to include("entire file")
      end

      it "calls a file entirely dead only when every relevant line is unhit" do
        File.write(input, JSON.dump("coverage" => {"lib/all.rb" => {"lines" => [0, 1]}}))
        SimpleCov::Production::FileSink.new(path: production_path).store("lib/other.rb" => [1])

        ok!(run_dead_code)

        expect(stdout.string).to include("entire file")
      end

      it "leaves a file with one line still running out of the entire-file mark" do
        File.write(input, JSON.dump("coverage" => {"lib/some.rb" => {"lines" => [0, 1]}}))
        SimpleCov::Production::FileSink.new(path: production_path).store("lib/some.rb" => [2])

        ok!(run_dead_code)

        expect(stdout.string).not_to include("entire file")
      end
    end

    describe "reporting what it could not read" do
      it "errors on a report it could not find" do
        expect(run("dead-code", "--input", absent, "--production", production_path)).to eq(1)
      end

      it "names it, under its own name" do
        run("dead-code", "--input", absent, "--production", production_path)

        expect(stderr.string).to eq("simplecov dead-code: #{absent} not found\n")
      end

      it "names the production file it could not find" do
        absent = File.join(tmp, "absent-production.json")

        exited!(1, run("dead-code", "--input", input, "--production", absent))

        expect(stderr.string).to eq("simplecov dead-code: #{absent} not found\n")
      end

      it "refuses a stray positional argument, naming the first one" do
        exited!(1, run_dead_code("stray", "another"))

        expect(stderr.string).to eq("simplecov dead-code: unexpected argument \"stray\"\n")
      end
    end

    context "with a production file it could not read" do
      before do
        File.write(production_path, "not json at all")
        exited!(1, run_dead_code)
      end

      it "reports it under its own name" do
        expect(stderr.string).to start_with("simplecov dead-code:")
      end

      it "keeps the raw exception out of the message" do
        expect(stderr.string).not_to include("#<")
      end
    end

    it "sorts the lines of a file the report never tracked" do
      File.write(input, JSON.dump("coverage" => {}))
      write_production(coverage: {"lib/prod_only.rb" => [9, 2, 5]})

      ok!(run_dead_code("--untested-in-production"))

      expect(stdout.string).to include("lib/prod_only.rb:2,5,9")
    end

    context "with more than one production-only file" do
      let(:listed) do
        File.write(input, JSON.dump("coverage" => {}))
        SimpleCov::Production::FileSink.new(path: production_path).store(
          "lib/zebra.rb" => [9, 2], "lib/apple.rb" => [4]
        )
        ok!(run_dead_code("--untested-in-production"))
        stdout.string.lines.grep(/\.rb:/).map(&:strip)
      end

      it "sorts the files" do
        expect(listed.first).to start_with("lib/apple.rb:4")
      end

      it "sorts each file's lines" do
        expect(listed.last).to start_with("lib/zebra.rb:2,9")
      end
    end

    def run_dead_code(*extra)
      run("dead-code", "--input", input, "--production", production_path, *extra)
    end

    def last_run(file)
      SimpleCov::Production::FileSink.read(production_path).fetch("last_seen").fetch(file)[0, 10]
    end

    context "with dead and possibly dead lines" do
      before { ok!(run_dead_code) }

      it "heads the dead section" do
        expect(stdout.string).to include("Dead code (not run in production, not covered by tests):")
      end

      it "prints a dead row with its stamp" do
        expect(stdout.string).to include("  lib/mixed.rb:2 (last run #{last_run("lib/mixed.rb")})\n")
      end

      it "heads the possibly dead section" do
        expect(stdout.string).to include("Possibly dead (not run in production, covered only by tests):")
      end

      it "prints a possibly dead row with its stamp" do
        expect(stdout.string).to include("  lib/mixed.rb:4 (last run #{last_run("lib/mixed.rb")})\n")
      end

      it "counts both at the end" do
        expect(stdout.string).to include("1 dead line, 3 possibly dead lines")
      end
    end

    context "with a file whose every relevant line skipped production" do
      before { ok!(run_dead_code) }

      it "marks it as an entire file" do
        expect(stdout.string).to include("  lib/tested_unused.rb:1-2 (entire file)\n")
      end

      it "keeps the production-only rows out" do
        expect(stdout.string).not_to include("prod_only")
      end

      it "keeps the ignored files out" do
        expect(stdout.string).not_to include("ignored.rb")
      end
    end

    it "combines the entire-file marker with the file's last production activity" do
      SimpleCov::Production::FileSink.new(path: production_path).store("lib/tested_unused.rb" => [9])

      run_dead_code

      expect(stdout.string)
        .to include("  lib/tested_unused.rb:1-2 (entire file, last run #{last_run("lib/tested_unused.rb")})\n")
    end

    context "when the store carries no stamps" do
      before do
        document = JSON.parse(File.read(production_path))
        document[SimpleCov::Production::FileSink::ENVELOPE].delete("last_seen")
        File.write(production_path, JSON.dump(document))
        ok!(run_dead_code)
      end

      it "prints the row bare" do
        expect(stdout.string).to include("  lib/mixed.rb:2\n")
      end

      it "leaves the annotation off" do
        expect(stdout.string).not_to include("last run")
      end
    end

    it "names the production file in the header" do
      ok!(run_dead_code)

      expect(stdout.string).to include("Production coverage: #{production_path}")
    end

    it "names its window beside it" do
      ok!(run_dead_code)
      window = SimpleCov::Production::FileSink.read(production_path)

      expect(stdout.string).to include("window #{window.fetch("started_at")} to #{window.fetch("updated_at")}")
    end

    context "with --untested-in-production" do
      before { ok!(run_dead_code("--untested-in-production")) }

      it "heads the section" do
        expect(stdout.string).to include("Untested code running in production:")
      end

      it "prints a row for a file the tests also cover" do
        expect(stdout.string).to include("  lib/mixed.rb:5 (last run #{last_run("lib/mixed.rb")})\n")
      end

      it "prints a row for a file only production ran" do
        expect(stdout.string).to include("  lib/prod_only.rb:3-4 (last run #{last_run("lib/prod_only.rb")})\n")
      end

      it "counts them at the end" do
        expect(stdout.string).to include("3 untested lines running in production")
      end

      it "leaves the dead-code section out" do
        expect(stdout.string).not_to include("Dead code")
      end
    end

    context "with --json" do
      let(:store) { SimpleCov::Production::FileSink.read(production_path).fetch("last_seen") }
      let(:data) { JSON.parse(stdout.string) }

      before { ok!(run_dead_code("--json")) }

      it "emits the dead category with the full stamps" do
        expect(data.fetch("dead"))
          .to eq([{"file" => "lib/mixed.rb", "lines" => [2], "last_seen" => store.fetch("lib/mixed.rb")}])
      end

      it "emits the possibly dead category" do
        expect(data.fetch("possibly_dead")).to eq(
          [{"file" => "lib/mixed.rb", "lines" => [4], "last_seen" => store.fetch("lib/mixed.rb")},
            {"file" => "lib/tested_unused.rb", "lines" => [1, 2]}]
        )
      end

      it "emits the untested-in-production category" do
        expect(data.fetch("untested_in_production")).to eq(
          [{"file" => "lib/mixed.rb", "lines" => [5], "last_seen" => store.fetch("lib/mixed.rb")},
            {"file" => "lib/prod_only.rb", "lines" => [3, 4], "last_seen" => store.fetch("lib/prod_only.rb")}]
        )
      end

      it "emits the window" do
        expect(data.fetch("window")).to include("started_at", "updated_at")
      end
    end

    it "reports the happy emptiness when nothing is dead" do
      SimpleCov::Production::FileSink.new(path: production_path).store(
        "lib/mixed.rb" => [2, 4], "lib/tested_unused.rb" => [1, 2]
      )

      ok!(run_dead_code)

      expect(stdout.string).to include("No dead code found.")
    end

    it "reports the happy emptiness for the untested view too" do
      FileUtils.rm(production_path)
      SimpleCov::Production::FileSink.new(path: production_path).store("lib/mixed.rb" => [1, 4])

      ok!(run_dead_code("--untested-in-production"))

      expect(stdout.string).to include("No untested production code found.")
    end

    it "skips report entries without line data" do
      File.write(input, JSON.dump("coverage" => {"lib/branch_only.rb" => {"branches" => []}}))

      ok!(run_dead_code)

      expect(stdout.string).not_to include("branch_only")
    end

    context "when the store carries no timestamps" do
      before do
        File.write(production_path, JSON.dump(
          SimpleCov::Production::FileSink::ENVELOPE => {
            "format_version" => 1, "coverage" => {"lib/mixed.rb" => [1]}
          }
        ))
        ok!(run_dead_code)
      end

      it "still names the production file" do
        expect(stdout.string).to include("Production coverage: #{production_path}\n")
      end

      it "omits the window from the header" do
        expect(stdout.string).not_to include("window")
      end
    end

    it "defaults --production to the project's configured production_coverage" do
      File.write(File.join(tmp, ".simplecov"), %(SimpleCov.production_coverage #{production_path.inspect}\n))
      Dir.chdir(tmp) { ok!(run("dead-code", "--input", input)) }

      expect(stdout.string).to include("Production coverage: #{production_path}")
    end

    context "with both an explicit --production and a configured store" do
      before do
        other = File.join(tmp, "other.json")
        SimpleCov::Production::FileSink.new(path: other).store("lib/other.rb" => [1])
        File.write(File.join(tmp, ".simplecov"), %(SimpleCov.production_coverage #{other.inspect}\n))
        Dir.chdir(tmp) { ok!(run_dead_code) }
      end

      it "prefers the explicit one" do
        expect(stdout.string).to include("Production coverage: #{production_path}")
      end

      it "leaves the configured one alone" do
        expect(stdout.string).not_to include("other.json")
      end
    end

    it "errors without --production when the project configures no store" do
      Dir.chdir(tmp) { expect(run("dead-code", "--input", input)).to eq(1) }
    end

    it "names the flag and the setting that would answer for it" do
      Dir.chdir(tmp) { run("dead-code", "--input", input) }

      expect(stderr.string).to include("simplecov dead-code: missing --production").and include("production_coverage")
    end

    it "errors when the production file is missing" do
      FileUtils.rm(production_path)

      exited!(1, run_dead_code)

      expect(stderr.string).to include("simplecov dead-code:").and include("not found")
    end

    it "errors when the production file is not a production store" do
      File.write(production_path, JSON.dump("coverage" => {}))

      exited!(1, run_dead_code)

      expect(stderr.string).to include("not a SimpleCov production coverage file")
    end

    it "rejects a stray positional argument" do
      exited!(1, run("dead-code", "--production", production_path, "stray"))

      expect(stderr.string).to include('unexpected argument "stray"')
    end
  end

  describe "CoverageFile.lookup", mutant_expression: "SimpleCov::CLI::CoverageFile*" do
    def lookup(hash, path)
      SimpleCov::CLI::CoverageFile.lookup(hash, path)
    end

    it "matches an absolute path exactly" do
      key = File.expand_path("some/file.rb")
      expect(lookup({key => "V"}, "some/file.rb")).to eq([key, "V"])
    end

    it "matches the literal path exactly" do
      expect(lookup({"lib/a.rb" => "V"}, "lib/a.rb")).to eq(["lib/a.rb", "V"])
    end

    it "falls back to a subpath suffix match" do
      expect(lookup({"/elsewhere/lib/a.rb" => "V"}, "lib/a.rb")).to eq(["/elsewhere/lib/a.rb", "V"])
    end

    it "prefers an exact match over an earlier suffix match" do
      hash = {"/x/vendor/lib/a.rb" => "VENDOR", File.expand_path("lib/a.rb") => "REAL"}
      expect(lookup(hash, "lib/a.rb").last).to eq("REAL")
    end

    it "returns nil for an ambiguous suffix match" do
      hash = {"app/models/foo.rb" => "APP", "lib/models/foo.rb" => "LIB"}
      expect(lookup(hash, "models/foo.rb")).to be_nil
    end

    it "returns nil when nothing matches" do
      expect(lookup({"other.rb" => "V"}, "missing.rb")).to be_nil
    end

    it "does not let a subpath match the end of a longer filename" do
      expect(lookup({"/x/barfoo.rb" => "V"}, "foo.rb")).to be_nil
    end

    it "still matches a subpath at a segment boundary" do
      expect(lookup({"/x/foo.rb" => "V"}, "foo.rb")).to eq(["/x/foo.rb", "V"])
    end

    describe "the failure message" do
      def message(hash, path)
        SimpleCov::CLI::CoverageFile.not_found_message(hash, path, "coverage/coverage.json")
      end

      it "names every candidate of an ambiguous subpath, sorted" do
        hash = {"lib/models/foo.rb" => "LIB", "app/models/foo.rb" => "APP"}

        expect(message(hash, "models/foo.rb")).to eq(
          "models/foo.rb matches 2 files in coverage/coverage.json: " \
          "app/models/foo.rb, lib/models/foo.rb (use a longer path to pick one)"
        )
      end

      it "reports a path nothing matches as simply absent" do
        expect(message({"other.rb" => "V"}, "missing.rb"))
          .to eq("no entry for missing.rb in coverage/coverage.json")
      end

      it "reports a single suffix match as absent rather than ambiguous" do
        expect(message({"/x/lib/a.rb" => "V"}, "lib/a.rb"))
          .to eq("no entry for lib/a.rb in coverage/coverage.json")
      end
    end

    describe "the exact index" do
      def index(hash)
        SimpleCov::CLI::CoverageFile.exact_index(hash)
      end

      it "holds every key under its own spelling" do
        expect(index({"lib/a.rb" => "A", "lib/b.rb" => "B"}))
          .to include("lib/a.rb" => "A", "lib/b.rb" => "B")
      end

      it "holds a real path under the spelling it was given" do
        indexed_real_path { |built, file| expect(built[file]).to eq("A") }
      end

      it "holds it under its resolved spelling too" do
        indexed_real_path { |built, file| expect(built[File.realdirpath(file)]).to eq("A") }
      end

      def indexed_real_path
        Dir.mktmpdir("simplecov-exact-index-") do |dir|
          file = File.join(dir, "a.rb")
          File.write(file, "x")
          yield(index({file => "A"}), file)
        end
      end

      it "keeps the literal spelling of a key whose file is gone" do
        expect(index({"/nonexistent/gone.rb" => "A"})).to eq("/nonexistent/gone.rb" => "A")
      end

      it "lets the first entry keep a resolved spelling two keys share" do
        indexed_through_a_link do |built, real, _linked|
          expect(built[File.realdirpath(File.join(real, "a.rb"))]).to eq("REAL")
        end
      end

      it "keeps the second entry under its own spelling" do
        indexed_through_a_link do |built, _real, linked|
          expect(built[File.join(linked, "a.rb")]).to eq("VIA_LINK")
        end
      end

      def indexed_through_a_link
        Dir.mktmpdir("simplecov-exact-index-link-") do |dir|
          real = File.join(dir, "real")
          linked = File.join(dir, "linked")
          FileUtils.mkdir_p(real)
          File.write(File.join(real, "a.rb"), "x")
          FileUtils.ln_s(real, linked)
          yield(index(File.join(real, "a.rb") => "REAL", File.join(linked, "a.rb") => "VIA_LINK"), real, linked)
        end
      end
    end

    describe "reporting an unusable input file" do
      let(:stderr) { StringIO.new }

      it "answers nothing for a missing file" do
        expect(SimpleCov::CLI::CoverageFile.load_document("/nope.json", command: "report", stderr: stderr))
          .to be_nil
      end

      it "names it under the command that looked for it" do
        SimpleCov::CLI::CoverageFile.load_document("/nope.json", command: "report", stderr: stderr)

        expect(stderr.string).to eq("simplecov report: /nope.json not found\n")
      end

      it "answers nothing for an unreadable file" do
        unreadable { |dir| expect(load_report(dir)).to be_nil }
      end

      it "names it and the reason" do
        unreadable do |dir|
          load_report(dir)

          expect(stderr.string).to start_with("simplecov report: cannot read #{dir.inspect} (")
        end
      end

      it "says it on one line" do
        unreadable do |dir|
          load_report(dir)

          expect(stderr.string.lines.length).to eq(1)
        end
      end

      def unreadable(&)
        Dir.mktmpdir("simplecov-unreadable-", &)
      end

      def load_report(path)
        SimpleCov::CLI::CoverageFile.load_document(path, command: "report", stderr: stderr)
      end

      it "reduces a multi-line reason to its first line" do
        SimpleCov::CLI::CoverageFile.report_invalid(stderr, "report", "x.json", "first line\nsecond line")

        expect(stderr.string).to eq(%(simplecov report: input file "x.json" isn't valid JSON (first line)\n))
      end

      it "trims the reason at both ends, not just the right" do
        SimpleCov::CLI::CoverageFile.report_invalid(stderr, "report", "x.json", "  padded  \nrest")

        expect(stderr.string).to eq(%(simplecov report: input file "x.json" isn't valid JSON (padded)\n))
      end

      it "trims an unreadable reason at both ends too" do
        SimpleCov::CLI::CoverageFile.report_unreadable(stderr, "report", "x.json", "  padded  \nrest")

        expect(stderr.string).to eq(%(simplecov report: cannot read "x.json" (padded)\n))
      end

      it "reads a document with no coverage section as carrying none" do
        without_coverage_section { |path| expect(load_coverage(path)).to eq({}) }
      end

      it "says nothing about it" do
        without_coverage_section do |path|
          load_coverage(path)

          expect(stderr.string).to be_empty
        end
      end

      def without_coverage_section
        Dir.mktmpdir("simplecov-no-coverage-") do |dir|
          path = File.join(dir, "coverage.json")
          File.write(path, JSON.dump("meta" => {}))
          yield(path)
        end
      end

      def load_coverage(path)
        SimpleCov::CLI::CoverageFile.load_coverage(path, command: "report", stderr: stderr)
      end

      it "reports a reason that is empty" do
        SimpleCov::CLI::CoverageFile.report_invalid(stderr, "report", "x.json", "")

        expect(stderr.string).to eq(%(simplecov report: input file "x.json" isn't valid JSON ()\n))
      end

      it "reports an unreadable reason that is empty" do
        SimpleCov::CLI::CoverageFile.report_unreadable(stderr, "report", "x.json", "")

        expect(stderr.string).to eq(%(simplecov report: cannot read "x.json" ()\n))
      end

      it "names the command when refusing a coverage section" do
        Dir.mktmpdir("simplecov-bad-coverage-") do |dir|
          path = refuse_coverage_in(dir)

          expect(stderr.string).to eq(bad_coverage_complaint(path))
        end
      end

      def refuse_coverage_in(dir)
        path = File.join(dir, "coverage.json")
        File.write(path, JSON.dump("coverage" => "junk"))
        SimpleCov::CLI::CoverageFile.load_coverage(path, command: "uncovered", stderr: stderr)
        path
      end

      def bad_coverage_complaint(path)
        %(simplecov uncovered: input file #{path.inspect} isn't valid JSON ) +
          %(("coverage" must be an object)\n)
      end

      it "accepts a coverage section that arrives as a Hash subclass" do
        coverage = Class.new(Hash).new.merge!("lib/a.rb" => {})
        allow(SimpleCov::CoverageJSON).to receive(:load).and_return("coverage" => coverage)

        expect(SimpleCov::CLI::CoverageFile.load_coverage("x.json", command: "report", stderr: stderr))
          .to eq(coverage)
      end

      it "reduces a multi-line unreadable reason too" do
        SimpleCov::CLI::CoverageFile.report_unreadable(stderr, "report", "x.json", "first line\nsecond line")

        expect(stderr.string).to eq(%(simplecov report: cannot read "x.json" (first line)\n))
      end
    end
  end

  describe "patch output", mutant_expression: "SimpleCov::CLI::Patch::Output*" do
    let(:stdout) { StringIO.new }
    let(:rows) do
      [{file: "lib/a.rb",
        line: {covered: 22, relevant: 25, missing: [41, 42, 43, 47]},
        branch: {covered: 1, relevant: 2, missing: [39]},
        method: nil},
        {file: "lib/b.rb",
         line: {covered: 4, relevant: 4, missing: []},
         branch: nil,
         method: {covered: 0, relevant: 0, missing: []}}]
    end
    let(:tied_rows) do
      [
        {file: "a.rb", line: {covered: 1, relevant: 1, missing: []}, branch: nil, method: nil},
        {file: "z.rb", line: {covered: 0, relevant: 2, missing: [1, 2]}, branch: nil, method: nil},
        {file: "m.rb", line: {covered: 0, relevant: 2, missing: [1, 2]}, branch: nil, method: nil}
      ]
    end

    def renderer = SimpleCov::CLI::Patch::Output

    def json_report_as_strings
      [{"file" => "lib/a.rb",
        "line" => {"covered" => 22, "relevant" => 25, "missing" => [41, 42, 43, 47], "percent" => 88.0},
        "branch" => {"covered" => 1, "relevant" => 2, "missing" => [39], "percent" => 50.0}},
        {"file" => "lib/b.rb",
         "line" => {"covered" => 4, "relevant" => 4, "missing" => [], "percent" => 100.0}}]
    end

    def text_report
      [
        "   88.00% (22/25) lines   50.00% (1/2) branches  lib/a.rb  missing 41-43, 47  branch 39",
        "  100.00% (4/4) lines  lib/b.rb",
        "  Patch coverage:  89.66% (26/29) lines,  50.00% (1/2) branches"
      ].join("\n").concat("\n")
    end

    def json_report
      [{file: "lib/a.rb",
        line: {covered: 22, relevant: 25, missing: [41, 42, 43, 47], percent: 88.0},
        branch: {covered: 1, relevant: 2, missing: [39], percent: 50.0}},
        {file: "lib/b.rb",
         line: {covered: 4, relevant: 4, missing: [], percent: 100.0}}]
    end

    it "prints the rows worst first, with a total beneath them" do
      renderer.emit_text(stdout, rows, false)

      expect(stdout.string).to eq(text_report)
    end

    it "sorts by coverage first and by filename only to break a tie" do
      renderer.emit_text(stdout, tied_rows, false)

      expect(stdout.string.lines.filter_map { |line| line[/\S+\.rb/] }).to eq(["m.rb", "z.rb", "a.rb"])
    end

    it "totals every criterion the rows measured, methods included" do
      with_methods = rows.collect { |row| row.merge(method: {covered: 1, relevant: 2, missing: [8]}) }
      renderer.emit_text(stdout, with_methods, false)

      expect(stdout.string.lines.last)
        .to eq("  Patch coverage:  89.66% (26/29) lines,  50.00% (1/2) branches,  50.00% (2/4) methods\n")
    end

    it "says so plainly when the change touched no coverable line" do
      renderer.emit_text(stdout, [], false)

      expect(stdout.string).to eq("simplecov patch: no coverable lines changed\n")
    end

    it "emits the same rows as data, each criterion carrying its percent" do
      expect(renderer.json_rows(rows)).to eq(json_report)
    end

    {
      [41, 42, 43, 47] => "41-43, 47",
      [1] => "1",
      [1, 3, 5] => "1, 3, 5",
      [1, 2] => "1-2"
    }.each do |lines, rendered|
      it "renders #{lines.inspect} as #{rendered.inspect}" do
        expect(renderer.ranges(lines)).to eq(rendered)
      end
    end

    it "joins the ranges with the separator it was given" do
      expect(renderer.ranges([1, 3], ",")).to eq("1,3")
    end

    it "falls back to a comma and a space" do
      expect(renderer.ranges([1, 3])).to eq("1, 3")
    end

    it "collapses a run before joining anything" do
      expect(renderer.ranges([1, 2, 3], ",")).to eq("1-3")
    end

    it "scores a change that touched nothing relevant as complete" do
      expect(renderer.pct(covered: 0, relevant: 0)).to eq(100.0)
    end

    it "scores a change that touched something as the fraction it covered" do
      expect(renderer.pct(covered: 1, relevant: 3)).to eq(33.33)
    end

    it "counts only the rows that measured a criterion into its total" do
      expect(renderer.sum_stats(rows, :branch)).to eq(covered: 1, relevant: 2)
    end

    it "counts every row that measured one" do
      expect(renderer.sum_stats(rows, :line)).to eq(covered: 26, relevant: 29)
    end

    it "reads no stats at all as unmeasured" do
      expect(renderer.measured?(nil)).to be false
    end

    it "reads stats with nothing relevant as unmeasured" do
      expect(renderer.measured?(covered: 0, relevant: 0)).to be false
    end

    it "reads stats with something relevant as measured" do
      expect(renderer.measured?(covered: 0, relevant: 1)).to be true
    end

    it "colorizes a shortfall red and a full cell green" do
      renderer.emit_text(stdout, rows, true)

      expect(stdout.string).to include("\e[31m 88.00%\e[0m").and include("\e[32m100.00%\e[0m")
    end

    it "colorizes the total line too" do
      renderer.emit_text(stdout, rows, true)

      expect(stdout.string.lines.last).to include("\e[31m 89.66%\e[0m")
    end

    it "counts a Hash subclass of statistics as measured" do
      expect(renderer.measured?(Class.new(Hash).new.merge!(covered: 0, relevant: 1))).to be true
    end

    it "colours a cell at or past complete green" do
      expect(renderer.criterion_cell("lines", {covered: 3, relevant: 2, missing: []}, true))
        .to include("\e[32m")
    end

    it "colours anything below it red" do
      expect(renderer.criterion_cell("lines", {covered: 199, relevant: 200, missing: []}, true))
        .to include("\e[31m")
    end

    it "colours every cell of a row, not only its first" do
      renderer.emit_text(stdout, rows, true)

      expect(stdout.string.lines.first).to include("\e[31m 88.00%\e[0m").and include("\e[31m 50.00%\e[0m")
    end

    it "colours a method cell too" do
      row = {file: "f", line: {covered: 1, relevant: 1, missing: []},
             branch: nil, method: {covered: 0, relevant: 2, missing: [3]}}

      expect(renderer.criterion_cells(row, true).last).to include("\e[31m")
    end

    it "asks about the stream it is writing to" do
      allow(described_class).to receive(:color_enabled?).and_return(false)

      renderer.emit(stdout, rows, json: false)

      expect(described_class).to have_received(:color_enabled?).with({json: false}, stdout)
    end

    it "notes nothing for a criterion that measured nothing" do
      row = {file: "f", line: {covered: 1, relevant: 1, missing: []},
             branch: {covered: 0, relevant: 0, missing: [3]}, method: nil}

      expect(renderer.missing_note(row)).to eq("")
    end

    it "leaves out a branch cell the change touched none of" do
      row = {file: "f", line: {covered: 1, relevant: 1, missing: []},
             branch: {covered: 0, relevant: 0, missing: []}, method: nil}

      expect(renderer.criterion_cells(row, false)).to eq(["100.00% (1/1) lines"])
    end

    describe "emit" do
      it "prints the rows as data under --json" do
        renderer.emit(stdout, rows, json: true)

        expect(JSON.parse(stdout.string)).to eq(json_report_as_strings)
      end

      it "prints them as text otherwise" do
        renderer.emit(stdout, rows, json: false, no_color: true)

        expect(stdout.string).to start_with("   88.00%")
      end

      it "leaves colour to the shared rule, which --no-color turns off" do
        renderer.emit(stdout, rows, json: false, no_color: true)
        expect(stdout.string).not_to include("\e[")
      end

      it "colorizes when the shared rule says to" do
        allow(described_class).to receive(:color_enabled?).and_return(true)
        renderer.emit(stdout, rows, json: false)
        expect(stdout.string).to include("\e[")
      end
    end

    describe "the minimum gate" do
      def row(covered, relevant, criterion: :line)
        base = {file: "lib/a.rb", line: {covered: 0, relevant: 0, missing: []}, branch: nil, method: nil}
        base.merge(criterion => {covered: covered, relevant: relevant, missing: []})
      end

      it "reports without gating when no minimum was asked for" do
        expect(renderer.gate([row(0, 10)], nil)).to eq(0)
      end

      it "passes a patch that clears the floor" do
        expect(renderer.gate([row(9, 10)], 90)).to eq(0)
      end

      it "fails one that does not" do
        expect(renderer.gate([row(8, 10)], 90)).to eq(1)
      end

      it "holds branches to the floor, not just lines" do
        expect(renderer.gate([row(10, 10).merge(branch: {covered: 0, relevant: 2, missing: []})], 100)).to eq(1)
      end

      it "holds methods to it too" do
        expect(renderer.gate([row(10, 10).merge(method: {covered: 0, relevant: 1, missing: []})], 100)).to eq(1)
      end

      it "reads a criterion the change touched none of as never short" do
        expect(renderer.short?({covered: 0, relevant: 0}, 100)).to be false
      end

      it "never fails over one" do
        expect(renderer.gate([row(10, 10)], 100)).to eq(0)
      end

      it "fails a patch that is short by a line however small the shortfall" do
        expect(renderer.short?({covered: 19_999, relevant: 20_000}, 100)).to be true
      end

      it "passes a patch sitting exactly on the floor" do
        expect(renderer.short?({covered: 23, relevant: 40}, 57.5)).to be false
      end

      it "passes a floor whose decimal has no exact binary form" do
        expect(renderer.short?({covered: 161, relevant: 250}, 64.4)).to be false
      end
    end

    describe "the cells and notes a row carries" do
      it "prints a branch and a method cell when the change touched both" do
        expect(renderer.criterion_cells(every_cell, false))
          .to eq([" 50.00% (1/2) lines", " 25.00% (1/4) branches", " 75.00% (3/4) methods"])
      end

      it "prints neither when the change touched neither" do
        untouched = every_cell.merge(branch: nil, method: {covered: 0, relevant: 0, missing: []})

        expect(renderer.criterion_cells(untouched, false)).to eq([" 50.00% (1/2) lines"])
      end

      def every_cell
        {file: "f", line: {covered: 1, relevant: 2, missing: [2]},
         branch: {covered: 1, relevant: 4, missing: [3]},
         method: {covered: 3, relevant: 4, missing: [7]}}
      end

      it "notes the missing lines, then each measured criterion's own" do
        row = {file: "f", line: {covered: 0, relevant: 2, missing: [1, 2]},
               branch: {covered: 0, relevant: 1, missing: [5]},
               method: {covered: 0, relevant: 1, missing: [9]}}
        expect(renderer.missing_note(row)).to eq("missing 1-2  branch 5  method 9")
      end

      it "notes only the criteria that actually missed something" do
        row = {file: "f", line: {covered: 2, relevant: 2, missing: []},
               branch: {covered: 2, relevant: 2, missing: []},
               method: {covered: 0, relevant: 1, missing: [4]}}
        expect(renderer.missing_note(row)).to eq("method 4")
      end

      it "says nothing about a row with nothing missing" do
        expect(renderer.missing_note(complete_row)).to eq("")
      end

      it "formats it without a missing note" do
        expect(renderer.format_row(complete_row, false)).to eq("  100.00% (1/1) lines  f")
      end

      def complete_row
        {file: "f", line: {covered: 1, relevant: 1, missing: []}, branch: nil, method: nil}
      end
    end
  end

  describe "patch subcommand", mutant_expression: "SimpleCov::CLI::Patch*" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-patch-spec-") }
    let(:cov) { File.join(tmp, "coverage.json") }

    after { FileUtils.rm_rf(tmp) }

    def git(*args)
      output, status = Open3.capture2e("git", "-C", tmp, *args)
      raise "git #{args.join(" ")} failed: #{output}" unless status.success?

      output
    end

    def build_repo(base:, head:, line_hits:, branches: nil, methods: nil, file: "lib/foo.rb", cover: true)
      init_repo
      write(file, base)
      commit("base")
      git("checkout", "-q", "-b", "feature")
      write(file, head)
      commit("head")
      write_report(file, line_hits, branches, methods) if cover
    end

    def init_repo
      GitFixture.init_repo(tmp)
    end

    def commit(message)
      git("add", "-A")
      git("commit", "-qm", message)
    end

    def write_report(file, line_hits, branches, methods = nil)
      payload = {"lines" => line_hits}
      payload["branches"] = branches if branches
      payload["methods"] = methods if methods
      write_coverage(File.join(tmp, file) => payload)
    end

    def write(rel, content)
      path = File.join(tmp, rel)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end

    def write_coverage(files)
      coverage = files.transform_values { |value| value.is_a?(Hash) ? value : {"lines" => value} }
      File.write(cov, JSON.dump("coverage" => coverage))
    end

    def run_in_repo(*argv)
      Dir.chdir(tmp) { run(*argv) }
    end

    context "with a change that touched some covered and some uncovered lines" do
      before do
        build_repo(base: "a\n", head: "a\nb\nc\n", line_hits: [1, 1, 0])
        ok!(run_in_repo("patch", "--base", "main", "--input", cov))
      end

      it "reports coverage over only the touched lines" do
        expect(stdout.string).to include("(1/2)").and include("missing 3")
      end

      it "totals the patch beneath them" do
        expect(stdout.string).to match(%r{Patch coverage:\s+50\.00%\s+\(1/2\)})
      end
    end

    it "collapses consecutive missed lines into a range" do
      build_repo(base: "a\n", head: "a\nb\nc\nd\n", line_hits: [1, 0, 0, 0])

      run_in_repo("patch", "--base", "main", "--input", cov)
      expect(stdout.string).to include("missing 2-4")
    end

    it "excludes never-relevant touched lines from the denominator" do
      build_repo(base: "a\n", head: "a\n# note\nb\n", line_hits: [1, nil, 1])

      run_in_repo("patch", "--base", "main", "--input", cov)
      expect(stdout.string).to match(%r{Patch coverage:\s+100\.00%\s+\(1/1\)})
    end

    it "exits non-zero below the --minimum floor" do
      build_repo(base: "a\n", head: "a\nb\nc\n", line_hits: [1, 1, 0])

      expect(run_in_repo("patch", "--base", "main", "--input", cov, "--minimum", "100")).to eq(1)
    end

    it "passes the --minimum gate when the floor is met" do
      build_repo(base: "a\n", head: "a\nb\nc\n", line_hits: [1, 1, 0])

      expect(run_in_repo("patch", "--base", "main", "--input", cov, "--minimum", "50")).to eq(0)
    end

    it "emits JSON rows under --json" do
      build_repo(base: "a\n", head: "a\nb\nc\n", line_hits: [1, 1, 0])

      run_in_repo("patch", "--base", "main", "--input", cov, "--json")
      rows = JSON.parse(stdout.string)
      expect(rows).to eq([{"file" => "lib/foo.rb",
                           "line" => {"covered" => 1, "relevant" => 2, "missing" => [3], "percent" => 50.0}}])
    end

    it "reports branch coverage over the touched branches" do
      build_repo(base: "a\n", head: "a\nif x\n  b\nend\n", line_hits: [1, 1, 1, nil],
        branches: [{"report_line" => 2, "coverage" => 1}, {"report_line" => 2, "coverage" => 0}])

      run_in_repo("patch", "--base", "main", "--input", cov)
      expect(stdout.string).to match(%r{50\.00%\s+\(1/2\)\s+branches}).and include("branch 2")
    end

    it "fails --minimum on an uncovered touched branch even when lines are covered" do
      build_repo(base: "a\n", head: "a\nif x\n  b\nend\n", line_hits: [1, 1, 1, nil],
        branches: [{"report_line" => 2, "coverage" => 1}, {"report_line" => 2, "coverage" => 0}])

      expect(run_in_repo("patch", "--base", "main", "--input", cov, "--minimum", "100")).to eq(1)
    end

    it "reports method coverage over the touched methods" do
      build_repo(base: "a\n", head: "a\ndef m\n  b\nend\n", line_hits: [1, 1, 1, nil],
        methods: [{"report_line" => 2, "coverage" => 1}, {"report_line" => 3, "coverage" => 0}])

      run_in_repo("patch", "--base", "main", "--input", cov)
      expect(stdout.string).to match(%r{50\.00%\s+\(1/2\)\s+methods}).and include("method 3")
    end

    it "fails --minimum on an uncovered touched method even when lines are covered" do
      build_repo(base: "a\n", head: "a\ndef m\n  b\nend\n", line_hits: [1, 1, 1, nil],
        methods: [{"report_line" => 2, "coverage" => 1}, {"report_line" => 3, "coverage" => 0}])

      expect(run_in_repo("patch", "--base", "main", "--input", cov, "--minimum", "100")).to eq(1)
    end

    it "includes the method stats in JSON rows" do
      build_repo(base: "a\n", head: "a\ndef m\n  b\nend\n", line_hits: [1, 1, 1, nil],
        methods: [{"report_line" => 2, "coverage" => 1}, {"report_line" => 3, "coverage" => 0}])

      run_in_repo("patch", "--base", "main", "--input", cov, "--json")
      expect(JSON.parse(stdout.string).first.fetch("method"))
        .to eq("covered" => 1, "relevant" => 2, "missing" => [3], "percent" => 50.0)
    end

    context "with a line-only report" do
      before do
        build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])
        ok!(run_in_repo("patch", "--base", "main", "--input", cov))
      end

      it "omits the branch column" do
        expect(stdout.string).not_to include("branches")
      end

      it "omits the method column" do
        expect(stdout.string).not_to include("methods")
      end
    end

    it "skips changed files the report does not track" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 0], file: "README.md", cover: false)
      write_coverage(File.join(tmp, "lib/other.rb") => [1])

      ok!(run_in_repo("patch", "--base", "main", "--input", cov))

      expect(stdout.string).to include("no coverable lines changed")
    end

    it "errors when the base ref cannot be resolved" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 0])

      exited!(1, run_in_repo("patch", "--base", "does-not-exist", "--input", cov))

      expect(stderr.string).to include("could not run `git diff`")
    end

    it "resolves an omitted --base through origin's HEAD" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])
      allow(SimpleCov::CLI::Git).to receive(:default_base).and_return("main")

      ok!(run_in_repo("patch", "--input", cov))

      expect(SimpleCov::CLI::Git).to have_received(:default_base)
    end

    it "errors when the coverage input is missing" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 0], cover: false)

      exited!(1, run_in_repo("patch", "--base", "main", "--input", cov))

      expect(stderr.string).to include(cov).and include("not found")
    end

    context "with --no-color, even with Color.enabled? on" do
      before do
        build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])
        allow(SimpleCov::Color).to receive(:enabled?).and_return(true)
        ok!(run_in_repo("patch", "--base", "main", "--input", cov, "--no-color"))
      end

      it "still prints its report" do
        expect(stdout.string).not_to be_empty
      end

      it "skips colorization" do
        expect(stdout.string).not_to include("\e[")
      end
    end

    it "follows a renamed file under --find-renames" do
      build_renamed_repo
      ok!(run_in_repo("patch", "--base", "main", "--input", cov, "--find-renames"))

      expect(stdout.string).to include("lib/new.rb").and include("missing 3")
    end

    def build_renamed_repo
      init_repo
      write("lib/old.rb", "a\nb\n")
      commit("base")
      git("checkout", "-q", "-b", "feature")
      git("mv", "lib/old.rb", "lib/new.rb")
      write("lib/new.rb", "a\nb\nc\n")
      commit("rename")
      write_report("lib/new.rb", [1, 1, 0], nil)
    end

    it "reports a git failure when git cannot be launched" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])
      allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT.new("git"))

      exited!(1, run_in_repo("patch", "--base", "main", "--input", cov))

      expect(stderr.string).to include("could not run `git diff`")
    end

    it "ignores a pure-deletion hunk" do
      build_repo(base: "a\nb\nc\n", head: "a\n", line_hits: [1])

      ok!(run_in_repo("patch", "--base", "main", "--input", cov))

      expect(stdout.string).to include("no coverable lines changed")
    end

    it "skips a file the change deletes" do
      build_deleting_repo
      ok!(run_in_repo("patch", "--base", "main", "--input", cov))

      expect(stdout.string).to include("no coverable lines changed")
    end

    def build_deleting_repo
      init_repo
      write("lib/gone.rb", "a\nb\n")
      commit("base")
      git("checkout", "-q", "-b", "feature")
      File.delete(File.join(tmp, "lib/gone.rb"))
      commit("delete")
      write_report("lib/gone.rb", [1, 0], nil)
    end

    it "drops a file whose touched lines are all never-relevant" do
      build_repo(base: "a\n", head: "a\n# note\n", line_hits: [1, nil])

      ok!(run_in_repo("patch", "--base", "main", "--input", cov))

      expect(stdout.string).to include("no coverable lines changed")
    end

    it "tolerates a coverage entry that isn't an object" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1], cover: false)
      File.write(cov, JSON.dump("coverage" => {File.join(tmp, "lib/foo.rb") => "malformed"}))

      ok!(run_in_repo("patch", "--base", "main", "--input", cov))

      expect(stdout.string).to include("no coverable lines changed")
    end

    it "skips malformed and off-change branch entries" do
      build_repo(base: "a\n", head: "a\nif x\n  b\nend\n", line_hits: [1, 1, 1, nil],
        branches: ["malformed", {"report_line" => 2, "coverage" => 1},
          {"report_line" => 99, "coverage" => 0}])

      run_in_repo("patch", "--base", "main", "--input", cov)
      expect(stdout.string).to match(%r{100\.00%\s+\(1/1\)\s+branches})
    end

    it "includes branch data in --json output" do
      build_repo(base: "a\n", head: "a\nif x\n  b\nend\n", line_hits: [1, 1, 1, nil],
        branches: [{"report_line" => 2, "coverage" => 1}, {"report_line" => 2, "coverage" => 0}])

      run_in_repo("patch", "--base", "main", "--input", cov, "--json")
      expect(JSON.parse(stdout.string).first["branch"])
        .to include("covered" => 1, "relevant" => 2, "percent" => 50.0)
    end

    it "shows 100% for a line cell with no coverable touched lines" do
      build_repo(base: "a\n", head: "a\nif x\n  b\n", line_hits: [1, nil, nil],
        branches: [{"report_line" => 2, "coverage" => 1}])

      run_in_repo("patch", "--base", "main", "--input", cov)
      expect(stdout.string).to match(%r{100\.00%\s+\(0/0\)\s+lines})
    end

    it "does not misread an added '++ ...' line as a file header" do
      diff = "diff --git a/lib/real.rb b/lib/real.rb\n" \
             "--- a/lib/real.rb\n+++ b/lib/real.rb\n" \
             "@@ -1,0 +2 @@\n+++ b/evil.rb\n" \
             "@@ -7 +8 @@\n-old\n+CHANGED\n"
      expect(SimpleCov::CLI::Patch::ChangedLines.parse_diff(diff)).to eq("lib/real.rb" => [2, 8])
    end

    [
      [{covered: 23, relevant: 40}, 57.5, false],
      [{covered: 22, relevant: 40}, 57.5, true],
      [{covered: 19_999, relevant: 20_000}, 100, true],
      [{covered: 20_000, relevant: 20_000}, 100, false],
      [{covered: 161, relevant: 250}, 64.4, false],
      [{covered: 160, relevant: 250}, 64.4, true]
    ].each do |stats, floor, short|
      it "reads #{stats.inspect} against #{floor} as #{short}" do
        expect(SimpleCov::CLI::Patch::Output.short?(stats, floor)).to be(short)
      end
    end

    it "refuses a --base that git would read as an option" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])

      exited!(1, run_in_repo("patch", "--base", "--output=/tmp/x", "--input", cov))

      expect(stderr.string).to include("could not run `git diff`")
    end

    it "passes --minimum when nothing coverable changed" do
      build_repo(base: "a\n", head: "a\n# note\n", line_hits: [1, nil])

      expect(run_in_repo("patch", "--base", "main", "--input", cov, "--minimum", "100")).to eq(0)
    end

    it "counts a rename as all-new without --find-renames" do
      build_renamed_repo
      ok!(run_in_repo("patch", "--base", "main", "--input", cov))

      expect(stdout.string).to include("(2/3)").and include("missing 3")
    end

    it "errors on a stray positional argument" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])

      exited!(1, run_in_repo("patch", "feature", "--input", cov))

      expect(stderr.string).to include("unexpected argument").and include("feature")
    end

    it "scores uncommitted working-tree changes" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1, 0])
      write("lib/foo.rb", "a\nb\nc\n")

      run_in_repo("patch", "--base", "main", "--input", cov)
      expect(stdout.string).to include("(1/2)").and include("missing 3")
    end

    it "reports on a change whose diff carries non-UTF-8 bytes" do
      build_repo(base: "a\n", head: "a\ns = \"caf\xE9\"\n".b, line_hits: [1, 1])

      ok!(run_in_repo("patch", "--base", "main", "--input", cov))

      expect(stdout.string).to match(%r{Patch coverage:\s+100\.00%\s+\(1/1\)})
    end

    it "resolves changed paths exactly instead of by suffix" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 0], cover: false)
      write_coverage(File.join(tmp, "spec/fixtures/lib/foo.rb") => [0, 0])

      ok!(run_in_repo("patch", "--base", "main", "--input", cov))

      expect(stdout.string).to include("no coverable lines changed")
    end

    it "warns when a changed line lies beyond the report's lines" do
      build_repo(base: "a\n", head: "a\nb\nc\n", line_hits: [1])

      ok!(run_in_repo("patch", "--base", "main", "--input", cov))

      expect(stderr.string).to include("lib/foo.rb").and include("stale")
    end

    it "scores a brand-new untracked file before it is ever added" do
      build_untracked_repo("lib/brand_new.rb", "a\nb\n", [1, 0])
      ok!(run_in_repo("patch", "--base", "main", "--input", cov))

      expect(stdout.string).to include("lib/brand_new.rb").and include("(1/2)").and include("missing 2")
    end

    # A repository whose only change is one file git has never been told about.
    def build_untracked_repo(path, source, hits, ignored: false)
      init_repo
      write("lib/base.rb", "a\n")
      write(".gitignore", "#{path}\n") if ignored
      commit("base")
      write(path, source)
      write_report(path, hits, nil)
    end

    it "scrubs bytes from git that are not valid UTF-8" do
      allow(SimpleCov::CLI::Git)
        .to receive(:capture)
        .and_return([(+"lib/ca\xFFe.rb\0lib/ok.rb\0").force_encoding(Encoding::UTF_8), "", true])

      expect(SimpleCov::CLI::Patch::ChangedLines.send(:untracked_files, "/anywhere"))
        .to eq(["lib/ca\uFFFDe.rb", "lib/ok.rb"])
    end

    it "leaves an ignored file out of the untracked ones" do
      build_untracked_repo("lib/generated.rb", "a\n", [0], ignored: true)
      ok!(run_in_repo("patch", "--base", "main", "--input", cov, "--minimum", "100"))

      expect(stdout.string).not_to include("lib/generated.rb")
    end

    it "fails --minimum on an uncovered untracked file" do
      build_untracked_repo("lib/brand_new.rb", "a\n", [0])

      expect(run_in_repo("patch", "--base", "main", "--input", cov, "--minimum", "100")).to eq(1)
    end

    it "relays git's own words when the base ref cannot be resolved" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 0])

      exited!(1, run_in_repo("patch", "--base", "does-not-exist", "--input", cov))

      expect(stderr.string).to match(/bad revision|unknown revision/)
    end

    it "scores a path git C-quotes" do
      skip "a quote is not a legal filename character on Windows" if Gem.win_platform?

      file = 'lib/we"ird.rb'
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 0], file: file)

      ok!(run_in_repo("patch", "--base", "main", "--input", cov))

      expect(stdout.string).to include(file).and include("missing 2")
    end

    context "with an untracked file whose report entry carries no lines" do
      before do
        init_repo
        write("lib/base.rb", "a\n")
        commit("base")
        write("lib/brand_new.rb", "a\n")
        write_coverage(File.join(tmp, "lib/brand_new.rb") => {})
        ok!(run_in_repo("patch", "--base", "main", "--input", cov))
      end

      it "reads it as nothing to cover" do
        expect(stdout.string).to include("no coverable lines changed")
      end

      it "says nothing about it" do
        expect(stderr.string).to be_empty
      end
    end

    it "scores only branches for an entry that carries no lines array" do
      build_repo(base: "a\n", head: "a\nif x\n", line_hits: [], cover: false)
      write_coverage(File.join(tmp, "lib/foo.rb") => {"branches" => [{"report_line" => 2, "coverage" => 1}]})

      ok!(run_in_repo("patch", "--base", "main", "--input", cov))

      expect(stdout.string).to match(%r{100\.00%\s+\(0/0\)\s+lines}).and match(%r{100\.00%\s+\(1/1\)\s+branches})
    end

    it "errors outside a git working tree" do
      write_coverage(File.join(tmp, "lib/foo.rb") => [1])

      exited!(1, run_in_repo("patch", "--base", "main", "--input", cov))

      expect(stderr.string).to include("could not run `git diff`").and include("git working tree")
    end

    it "reports a git failure during the diff itself" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])
      stub_git_diff.and_raise(Errno::EIO, "lost the disk")
      exited!(1, run_in_repo("patch", "--base", "main", "--input", cov))

      expect(stderr.string).to include("could not run `git diff`").and include("lost the disk")
    end

    def stub_git_diff
      allow(Open3).to receive(:capture3).and_call_original
      allow(Open3).to receive(:capture3).with("git", "-C", anything, "-c", any_args)
    end

    it "keeps scoring the diff when the untracked listing fails" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])
      failed = instance_double(Process::Status, success?: false)
      stub_ls_files.and_return(["", "", failed])
      ok!(run_in_repo("patch", "--base", "main", "--input", cov))

      expect(stdout.string).to match(%r{Patch coverage:\s+100\.00%\s+\(1/1\)})
    end

    def stub_ls_files
      allow(Open3).to receive(:capture3).and_call_original
      allow(Open3).to receive(:capture3).with("git", "-C", anything, "ls-files", any_args)
    end

    it "keeps scoring the diff when the untracked listing raises" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])
      stub_ls_files.and_raise(Errno::EIO, "lost the disk")
      ok!(run_in_repo("patch", "--base", "main", "--input", cov))

      expect(stdout.string).to match(%r{Patch coverage:\s+100\.00%\s+\(1/1\)})
    end

    describe "a diff pinned against the repository's own configuration" do
      before { build_repo(base: "a\n", head: "a\nb\nc\n", line_hits: [1, 1, 0]) }

      {
        "colour turned on" => ["color.diff", "always"],
        "prefixes turned off" => ["diff.noprefix", "true"],
        "a source prefix of its own" => ["diff.srcPrefix", "src/"],
        "a destination prefix of its own" => ["diff.dstPrefix", "dst/"],
        "quoted paths" => ["core.quotePath", "true"],
        "context between hunks" => ["diff.interHunkContext", "5"],
        "renames found by default" => ["diff.renames", "true"]
      }.each do |description, (setting, value)|
        it "scores the same change with #{description}" do
          git("config", setting, value)

          ok!(run_in_repo("patch", "--base", "main", "--input", cov))

          expect(stdout.string).to match(%r{Patch coverage:\s+50\.00%\s+\(1/2\)})
        end
      end

      it "keeps hunks apart that a merged context would join" do
        build_repo_with_distant_hunks
        ok!(run_in_repo("patch", "--base", "main", "--input", cov))

        expect(stdout.string).to match(%r{Patch coverage:\s+100\.00%\s+\(2/2\)})
      end

      def build_repo_with_distant_hunks
        git("checkout", "-q", "main")
        write("lib/foo.rb", "a\nb\nc\nd\ne\n")
        commit("five lines")
        git("checkout", "-q", "-B", "feature")
        write("lib/foo.rb", "A\nb\nc\nd\nE\n")
        commit("both ends")
        write_report("lib/foo.rb", [1, 0, 0, 0, 1], nil)
        git("config", "diff.interHunkContext", "5")
      end

      it "scores the same change with an external diff driver configured" do
        git("config", "diff.external", "true")

        ok!(run_in_repo("patch", "--base", "main", "--input", cov))

        expect(stdout.string).to match(%r{Patch coverage:\s+50\.00%\s+\(1/2\)})
      end

      it "scores the same change with a textconv filter configured" do
        git("config", "diff.firstline.textconv", "head -1")
        write(".gitattributes", "*.rb diff=firstline\n")
        commit("textconv")

        ok!(run_in_repo("patch", "--base", "main", "--input", cov))

        expect(stdout.string).to match(%r{Patch coverage:\s+50\.00%\s+\(1/2\)})
      end

      it "scores against the merge base rather than the base's tip" do
        move_main_on
        write_report("lib/foo.rb", [1, 1, 0], nil)
        ok!(run_in_repo("patch", "--base", "main", "--input", cov))

        expect(stdout.string).to match(%r{Patch coverage:\s+50\.00%\s+\(1/2\)})
      end

      def move_main_on
        git("checkout", "-q", "main")
        write("lib/other.rb", "x\ny\n")
        commit("moved on")
        git("checkout", "-q", "feature")
      end
    end

    it "refuses a base that git would read as an option" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])

      exited!(1, run_in_repo("patch", "--base", "--output=/tmp/pwned", "--input", cov))

      expect(stderr.string)
        .to eq(%(simplecov patch: could not run `git diff` against "--output=/tmp/pwned" ) +
               %((a ref cannot begin with "-")\n))
    end

    context "when run outside a working tree" do
      def run_outside_a_repo
        File.write(cov, JSON.dump("coverage" => {}))
        plain = Dir.mktmpdir("simplecov-cli-patch-nogit-")
        Dir.chdir(plain) { run("patch", "--base", "main", "--input", cov) }
      ensure
        FileUtils.remove_entry(plain)
      end

      it "errors" do
        expect(run_outside_a_repo).to eq(1)
      end

      it "reports it once, naming the base" do
        run_outside_a_repo

        expect(stderr.string).to eq(%(simplecov patch: could not run `git diff` against "main" ) +
                                   %((is this a git working tree, and does the ref exist?)\n))
      end
    end

    it "names the subcommand when the report cannot be read" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])

      exited!(1, run_in_repo("patch", "--base", "main", "--input", "/no/such.json"))

      expect(stderr.string).to start_with("simplecov patch: ")
    end

    it "names the stray positional, and what to write instead" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])

      exited!(1, run_in_repo("patch", "feature-x", "other", "--input", cov))

      expect(stderr.string)
        .to eq(%(simplecov patch: unexpected argument "feature-x" (did you mean `--base feature-x`?)\n))
    end

    it "falls back to the repository's default branch" do
      build_repo(base: "a\n", head: "a\nb\nc\n", line_hits: [1, 1, 0])

      ok!(run_in_repo("patch", "--input", cov))

      expect(stdout.string).to match(%r{Patch coverage:\s+50\.00%\s+\(1/2\)})
    end

    it "takes a fractional minimum" do
      build_repo(base: "a\n", head: "a\nb\nc\n", line_hits: [1, 1, 0])

      expect(run_in_repo("patch", "--base", "main", "--input", cov, "--minimum", "50.5")).to eq(1)
      ok!(run_in_repo("patch", "--base", "main", "--input", cov, "--minimum", "49.5"))
    end

    it "refuses a minimum that is not a number" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])

      exited!(1, run_in_repo("patch", "--base", "main", "--input", cov, "--minimum", "lots"))

      expect(stderr.string).to include("invalid argument")
    end

    it "scores against the merge base, not against the base's tip" do
      build_repo_that_moved_on
      ok!(run_in_repo("patch", "--base", "main", "--input", cov))

      expect(stdout.string).to match(%r{Patch coverage:\s+0\.00%\s+\(0/1\)})
    end

    def build_repo_that_moved_on
      init_repo
      write("lib/foo.rb", "a\nb\n")
      commit("base")
      git("checkout", "-q", "-b", "feature")
      write("lib/foo.rb", "a\nb\nc\n")
      commit("head")
      git("checkout", "-q", "main")
      write("lib/foo.rb", "a\n")
      commit("main moved on")
      git("checkout", "-q", "feature")
      write_report("lib/foo.rb", [1, 0, 0], nil)
    end

    it "diffs a ref that shares its name with a file" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])
      write("main", "a file named like the branch\n")
      commit("ambiguous")
      ok!(run_in_repo("patch", "--base", "main", "--input", cov))

      expect(stdout.string).to match(%r{Patch coverage:\s+100\.00%\s+\(1/1\)})
    end

    it "scores a moved file as all-new" do
      build_moved_repo
      ok!(run_in_repo("patch", "--base", "main", "--input", cov))

      expect(stdout.string).to match(%r{Patch coverage:\s+66\.67%\s+\(2/3\)})
    end

    it "scores only what moved under --find-renames" do
      build_moved_repo
      ok!(run_in_repo("patch", "--base", "main", "--input", cov, "--find-renames"))

      expect(stdout.string).to match(%r{Patch coverage:\s+0\.00%\s+\(0/1\)})
    end

    def build_moved_repo
      init_repo
      write("lib/foo.rb", "a\nb\nc\n")
      commit("base")
      git("checkout", "-q", "-b", "feature")
      git("mv", "lib/foo.rb", "lib/bar.rb")
      write("lib/bar.rb", "a\nb\nd\n")
      commit("head")
      write_report("lib/bar.rb", [1, 1, 0], nil)
    end

    describe "counting a file's touched branches" do
      def entry_stats(entries, changed)
        SimpleCov::CLI::Patch.send(:entry_stats, entries, changed)
      end

      it "counts one missing line per line, however many arms missed it" do
        entries = [{"start_line" => 2, "coverage" => 0}, {"start_line" => 2, "coverage" => 0}]

        expect(entry_stats(entries, [2])).to eq(covered: 0, relevant: 2, missing: [2])
      end

      it "lists the missing lines in order, whatever order the entries arrived in" do
        entries = [{"start_line" => 5, "coverage" => 0}, {"start_line" => 2, "coverage" => 0}]

        expect(entry_stats(entries, [2, 5])).to eq(covered: 0, relevant: 2, missing: [2, 5])
      end

      [nil, 7].each do |entry|
        it "counts nothing for #{entry.inspect}, which is not a list" do
          expect(entry_stats(entry, [1])).to be_nil
        end
      end
    end

    describe "counting a file's touched lines" do
      def line_stats(hits, changed)
        SimpleCov::CLI::Patch.send(:line_stats, hits, changed)
      end

      it "lists the missing lines in order, whatever order they changed in" do
        expect(line_stats([0, 1, 0], [3, 1])).to eq(covered: 0, relevant: 2, missing: [1, 3])
      end

      it "counts only the lines the report can count" do
        expect(line_stats([1, nil, "junk", 0], [1, 2, 3, 4]))
          .to eq(covered: 1, relevant: 2, missing: [4])
      end

      [nil, "junk", 7].each do |lines|
        it "counts nothing at all for #{lines.inspect} in place of a line list" do
          expect(line_stats(lines, [1, 2])).to eq(covered: 0, relevant: 0, missing: [])
        end
      end
    end

    describe "matching a changed file to its report entry" do
      def rows(coverage, changes, root: "/repo")
        SimpleCov::CLI::Patch.send(:compute_rows, coverage, {root: root, changes: changes}, StringIO.new)
      end

      it "finds an entry keyed the way the diff names the file" do
        found = rows({"lib/a.rb" => {"lines" => [1, 0]}}, {"lib/a.rb" => [1, 2]})

        expect(found.map { |row| row[:file] }).to eq(["lib/a.rb"])
      end

      it "finds an entry keyed by its absolute path" do
        found = rows({File.expand_path("/repo/lib/a.rb") => {"lines" => [1, 0]}}, {"lib/a.rb" => [1, 2]})

        expect(found.map { |row| row[:file] }).to eq(["lib/a.rb"])
      end

      it "passes over a file the report does not carry" do
        expect(rows({"lib/other.rb" => {"lines" => [1]}}, {"lib/a.rb" => [1]})).to eq([])
      end

      ["junk", 7].each do |entry|
        it "passes over #{entry.inspect}, which is not an object" do
          expect(rows({"lib/a.rb" => entry}, {"lib/a.rb" => [1]})).to eq([])
        end
      end
    end

    describe "reading hunk headers" do
      def parse_diff(output)
        SimpleCov::CLI::Patch::ChangedLines.send(:parse_diff, output)
      end

      it "counts one line for a header that names no count" do
        diff = "diff --git a/lib/a.rb b/lib/a.rb\n+++ b/lib/a.rb\n@@ -1 +2 @@\n+b\n"

        expect(parse_diff(diff)).to eq("lib/a.rb" => [2])
      end

      it "counts the lines a header says it runs for" do
        diff = "diff --git a/lib/a.rb b/lib/a.rb\n+++ b/lib/a.rb\n@@ -1,0 +2,3 @@\n+b\n+c\n+d\n"

        expect(parse_diff(diff)).to eq("lib/a.rb" => [2, 3, 4])
      end

      it "counts nothing for a hunk that only deletes" do
        diff = "diff --git a/lib/a.rb b/lib/a.rb\n+++ b/lib/a.rb\n@@ -1,2 +1,0 @@\n-a\n-b\n"

        expect(parse_diff(diff)).to eq({})
      end

      it "reads the section's own header, not a line that looks like one" do
        diff = "diff --git a/lib/a.rb b/lib/a.rb\n+++ b/lib/a.rb\n@@ -1,0 +2 @@\n+++ not/a/header.rb\n"

        expect(parse_diff(diff)).to eq("lib/a.rb" => [2])
      end

      it "passes over a section for a file that is only deleted" do
        diff = "diff --git a/lib/a.rb b/lib/a.rb\n+++ /dev/null\n@@ -1,2 +0,0 @@\n-a\n-b\n"

        expect(parse_diff(diff)).to eq({})
      end

      it "keeps reading past a section it cannot name" do
        diff = "diff --git a/lib/gone.rb b/lib/gone.rb\n+++ /dev/null\n@@ -1 +0,0 @@\n-a\n" \
               "diff --git a/lib/no-header.rb b/lib/no-header.rb\n@@ -1,0 +1 @@\n+a\n" \
               "diff --git a/lib/kept.rb b/lib/kept.rb\n+++ b/lib/kept.rb\n@@ -1,0 +2 @@\n+b\n"

        expect(parse_diff(diff)).to eq("lib/kept.rb" => [2])
      end

      it "reads every hunk of a file, not just its first" do
        diff = "diff --git a/lib/a.rb b/lib/a.rb\n+++ b/lib/a.rb\n" \
               "@@ -1,0 +2 @@\n+b\n@@ -5,0 +7,2 @@\n+g\n+h\n"

        expect(parse_diff(diff)).to eq("lib/a.rb" => [2, 7, 8])
      end
    end

    describe "which lines a change touched" do
      def changed_for(lines, payload)
        SimpleCov::CLI::Patch.send(:changed_for, lines, payload)
      end

      it "counts each changed line once, however often the diff named it" do
        expect(changed_for([3, 1, 3], {"lines" => [1, 1, 1]})).to eq([3, 1])
      end

      it "takes every line of an untracked file the report carries" do
        expect(changed_for(:all, {"lines" => [1, nil, 0]})).to eq([1, 2, 3])
      end

      [{"lines" => nil}, {}, {"lines" => "junk"}, {"lines" => 7}].each do |entry|
        it "takes no lines from an untracked file the report records as #{entry.inspect}" do
          expect(changed_for(:all, entry)).to eq([])
        end
      end
    end

    describe "picking the touched entries out of a report" do
      def touched(entries, changed)
        found = []
        SimpleCov::CLI::Patch.send(:each_touched, entries, changed) { |line, hits| found << [line, hits] }
        found
      end

      it "reads an entry by its report line, falling back to where it starts" do
        entries = [{"report_line" => 3, "start_line" => 9, "coverage" => 1},
          {"start_line" => 4, "coverage" => 0},
          {"report_line" => 5, "coverage" => 2}]

        expect(touched(entries, [3, 4, 5])).to eq([[3, 1], [4, 0], [5, 2]])
      end

      it "passes over an entry that says nowhere at all" do
        expect(touched([{"coverage" => 1}, {"start_line" => 5, "coverage" => 2}], [5])).to eq([[5, 2]])
      end

      it "passes over an entry that carries no coverage at all" do
        expect(touched([{"start_line" => 4}, {"start_line" => 5, "coverage" => 1}], [4, 5])).to eq([[5, 1]])
      end

      it "passes over an entry that is not an object at all" do
        entries = [nil, "junk", [1, 2], {"start_line" => 4, "coverage" => 2}]

        expect(touched(entries, [4])).to eq([[4, 2]])
      end

      it "passes over an entry whose coverage is not a count" do
        entries = [{"start_line" => 4, "coverage" => nil}, {"start_line" => 5, "coverage" => "1"},
          {"start_line" => 6, "coverage" => 3}]

        expect(touched(entries, [4, 5, 6])).to eq([[6, 3]])
      end

      it "passes over an entry the change never touched" do
        expect(touched([{"start_line" => 9, "coverage" => 1}], [4])).to eq([])
      end
    end

    describe "noticing a stale report" do
      let(:stderr_io) { StringIO.new }

      def warn_stale(payload, changed)
        SimpleCov::CLI::Patch.send(:warn_stale, "lib/foo.rb", payload, changed, stderr_io)
        stderr_io.string
      end

      it "warns when a changed line is past the end of the entry" do
        expect(warn_stale({"lines" => [1, 1]}, [1, 3]))
          .to include("lib/foo.rb changed beyond the 2-line entry")
      end

      it "stays quiet when the last changed line is the entry's last" do
        expect(warn_stale({"lines" => [1, 1]}, [1, 2])).to be_empty
      end

      it "stays quiet when every changed line sits inside the entry" do
        expect(warn_stale({"lines" => [1, 1, 1]}, [1])).to be_empty
      end

      ["junk", 7].each do |lines|
        it "stays quiet about #{lines.inspect} in place of a line list" do
          expect(warn_stale({"lines" => lines}, [1, 3])).to be_empty
        end
      end

      it "stays quiet when nothing changed" do
        expect(warn_stale({"lines" => [1, 1]}, [])).to be_empty
      end

      it "stays quiet about an entry that carries no line list" do
        expect(warn_stale({"lines" => nil}, [1, 3])).to be_empty
      end

      it "warns on the furthest changed line, wherever it sits in the list" do
        expect(warn_stale({"lines" => [1, 1]}, [3, 1])).to include("changed beyond")
      end
    end

    describe "what counts as a scored row" do
      def scored?(line_relevant, branch: nil, method: nil)
        SimpleCov::CLI::Patch.send(:scored?, {line: {relevant: line_relevant}, branch: branch, method: method})
      end

      it "counts a row with a coverable touched line" do
        expect(scored?(1)).to be true
      end

      it "counts a row with only a touched branch" do
        expect(scored?(0, branch: {relevant: 2, covered: 1})).to be true
      end

      it "counts a row with only a touched method" do
        expect(scored?(0, method: {relevant: 1, covered: 1})).to be true
      end

      it "counts out a row that touched no lines" do
        expect(scored?(0)).to be false
      end

      it "counts out one whose other criteria are empty too" do
        expect(scored?(0, branch: {relevant: 0, covered: 0}, method: {relevant: 0, covered: 0})).to be false
      end
    end

    describe "reading a diff header's path" do
      subject(:diff_path) { SimpleCov::CLI::Patch::ChangedLines.method(:diff_path) }

      ["+++ b/lib/foo.rb\n", "--- a/lib/foo.rb\n"].each do |line|
        it "strips the prefix git was told to emit from #{line.strip.inspect}" do
          expect(diff_path.call(line)).to eq("lib/foo.rb")
        end
      end

      it "answers nothing for a side that is not there" do
        expect(diff_path.call("+++ /dev/null\n")).to be_nil
      end

      it "strips only the leading prefix, not one inside the path" do
        expect(diff_path.call("+++ b/lib/b/foo.rb\n")).to eq("lib/b/foo.rb")
      end

      it "reads a header that carries no newline" do
        expect(diff_path.call("+++ b/lib/foo.rb")).to eq("lib/foo.rb")
      end

      it "reads a header with nothing after the marker as no path at all" do
        expect(diff_path.call("+++")).to eq("")
      end

      it "unquotes a header path git had to quote" do
        expect(diff_path.call(%(+++ "b/we\\"ird.rb"\n))).to eq(%(we"ird.rb))
      end
    end

    describe "undoing git's C-quoting" do
      subject(:unquote) { SimpleCov::CLI::Patch::ChangedLines.method(:unquote) }

      {
        %("b/a\\tb.rb") => "b/a\tb.rb",
        %("b/caf\\303\\251.rb") => "b/café.rb",
        %("b/a\\zb.rb") => "b/azb.rb",
        %("b/we\\"ird.rb") => %(b/we"ird.rb),
        %("b/back\\\\slash.rb") => "b/back\\slash.rb",
        %("b/line\\nbreak.rb") => "b/line\nbreak.rb",
        %("b/ret\\rurn.rb") => "b/ret\rurn.rb",
        %("b/bel\\a.rb") => "b/bel\a.rb",
        %("b/back\\bspace.rb") => "b/back\bspace.rb",
        %("b/form\\ffeed.rb") => "b/form\ffeed.rb",
        %("b/vert\\vtab.rb") => "b/vert\vtab.rb",
        %("") => ""
      }.each do |quoted, unquoted|
        it "reads #{quoted} as #{unquoted.inspect}" do
          expect(unquote.call(quoted)).to eq(unquoted)
        end
      end

      ["b/plain.rb", %("b/half.rb), %(b/half.rb"), %("), ""].each do |raw|
        it "leaves #{raw.inspect} exactly as it is" do
          expect(unquote.call(raw)).to eq(raw)
        end
      end

      it "reads a path that mixes a real character with an escaped byte" do
        expect(unquote.call(%("b/\u00e9\\377.rb"))).to eq("b/\u00e9\uFFFD.rb")
      end

      it "answers a path whose bytes are not UTF-8 readable as UTF-8" do
        expect(unquote.call(%("b/latin\\351.rb")).encoding).to eq(Encoding::UTF_8)
      end

      it "keeps it, with the unreadable bytes replaced" do
        expect(unquote.call(%("b/latin\\351.rb"))).to eq("b/latin\uFFFD.rb")
      end
    end

    it "scores changes outside the current subdirectory" do
      build_two_directory_repo
      Dir.chdir(File.join(tmp, "lib")) { ok!(run("patch", "--base", "main", "--input", cov)) }

      expect(stdout.string).to include("lib/foo.rb").and include("app/bar.rb")
    end

    def build_two_directory_repo
      init_repo
      write("lib/foo.rb", "a\n")
      write("app/bar.rb", "a\n")
      commit("base")
      git("checkout", "-q", "-b", "feature")
      write("lib/foo.rb", "a\nb\n")
      write("app/bar.rb", "a\nb\n")
      commit("head")
      write_coverage(File.join(tmp, "lib/foo.rb") => [1, 1], File.join(tmp, "app/bar.rb") => [1, 0])
    end
  end

  describe "serve subcommand", mutant_expression: "SimpleCov::CLI::Serve*" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-serve-spec-") }
    let(:fake_client_class) do
      Class.new do
        attr_reader :written, :read_timeout, :closed

        def initialize(request)
          @lines = request.lines
          @written = +""
          @closed = false
        end

        def readline = (@lines.shift or raise EOFError)

        def write(*parts) = parts.each { |part| @written << part.to_s }

        def timeout=(seconds)
          @read_timeout = seconds
        end

        def close = @closed = true
      end
    end
    let(:viewer_document) do
      lines = {"covered" => 1, "missed" => 0, "total" => 1, "percent" => 100.0, "strength" => 1.0}
      {
        "meta" => {
          "simplecov_version" => SimpleCov::VERSION, "command_name" => "RSpec", "project_name" => "Example",
          "timestamp" => Time.now.iso8601, "line_coverage" => true,
          "branch_coverage" => false, "method_coverage" => false
        },
        "total" => {"lines" => lines},
        "coverage" => {"lib/a.rb" => {"source" => ["puts :ok"]}},
        "groups" => {}
      }
    end

    after { FileUtils.rm_rf(tmp) }

    it "errors when the coverage dir doesn't exist" do
      allow(described_class).to receive(:coverage_dir).and_return(File.join(tmp, "nope"))
      exited!(1, run("serve"))

      expect(stderr.string).to include("doesn't exist")
    end

    context "when the coverage dir has no report artifacts" do
      before do
        FileUtils.mkdir_p(tmp)
        allow(described_class).to receive(:coverage_dir).and_return(tmp)
        allow(TCPServer).to receive(:new).and_call_original
        exited!(1, run("serve"))
      end

      it "says what it wanted to find" do
        expect(stderr.string).to include("no index.html or coverage.json")
      end

      it "errors before binding" do
        expect(TCPServer).not_to have_received(:new)
      end
    end

    it "errors cleanly when the port is already taken" do
      FileUtils.mkdir_p(tmp)
      File.write(File.join(tmp, "index.html"), "report")
      allow(described_class).to receive(:coverage_dir).and_return(tmp)

      expect(taken_port_complaint).to include("simplecov serve: cannot bind to 127.0.0.1:")
    end

    def taken_port_complaint
      blocker = TCPServer.new("127.0.0.1", 0)
      exited!(1, run("serve", "--port", blocker.addr[1].to_s))
      stderr.string
    ensure
      blocker.close
    end

    context "with an index already built" do
      before do
        FileUtils.mkdir_p(tmp)
        File.write(File.join(tmp, "index.html"), "existing report")
        File.write(File.join(tmp, "coverage.json"), "{")
        allow(described_class).to receive(:coverage_dir).and_return(tmp)
        allow(described_class::Serve).to receive(:with_server).and_return(0)
        run!("serve")
      end

      it "leaves it alone, without inspecting coverage.json" do
        expect(File.read(File.join(tmp, "index.html"))).to eq("existing report")
      end

      it "serves it" do
        expect(described_class::Serve).to have_received(:with_server)
      end
    end

    context "with no index but a coverage.json" do
      before do
        FileUtils.mkdir_p(tmp)
        File.write(File.join(tmp, "coverage.json"), JSON.dump(servable_document))
        allow(described_class).to receive(:coverage_dir).and_return(tmp)
        allow(described_class::Serve).to receive(:with_server).and_return(0)
        run!("serve")
      end

      it "builds the index from it" do
        expect(File.read(File.join(tmp, "index.html"))).to include("window.SIMPLECOV_DATA")
      end

      it "serves it, having built it before binding" do
        expect(described_class::Serve).to have_received(:with_server)
      end
    end

    def servable_document
      {
        "meta" => {
          "simplecov_version" => SimpleCov::VERSION, "command_name" => "RSpec", "project_name" => "Example",
          "timestamp" => Time.now.iso8601, "line_coverage" => true,
          "branch_coverage" => false, "method_coverage" => false
        },
        "total" => {"lines" => {"covered" => 1, "missed" => 0, "total" => 1,
                                "percent" => 100.0, "strength" => 1.0}},
        "coverage" => {"lib/a.rb" => {"source" => ["puts :ok"]}},
        "groups" => {}
      }
    end

    it "requires the stdlib sockets on the way in" do
      allow(described_class::Serve).to receive(:require)

      described_class::Serve.send(:require_socket)

      expect(described_class::Serve).to have_received(:require).with("socket")
    end

    describe "preparing the report" do
      it "answers nothing when the index is already there" do
        FileUtils.mkdir_p(tmp)
        File.write(File.join(tmp, "index.html"), "existing")

        expect(preparer.call(tmp)).to be_nil
      end

      it "answers nothing once it has built the index itself" do
        FileUtils.mkdir_p(tmp)
        File.write(File.join(tmp, "coverage.json"), JSON.dump(viewer_document))

        expect(preparer.call(tmp)).to be_nil
      end

      it "leaves the index it built behind" do
        FileUtils.mkdir_p(tmp)
        File.write(File.join(tmp, "coverage.json"), JSON.dump(viewer_document))
        preparer.call(tmp)

        expect(File.read(File.join(tmp, "index.html"))).to include("window.SIMPLECOV_DATA")
      end

      it "names the directory that is not there" do
        missing = File.join(tmp, "nowhere")

        expect(preparer.call(missing)).to eq("#{missing} doesn't exist; run your test suite first")
      end

      it "names the directory that carries neither file" do
        FileUtils.mkdir_p(tmp)

        expect(preparer.call(tmp))
          .to eq("#{tmp} has no index.html or coverage.json; run your test suite first")
      end

      it "names the file it could not build from, and what went wrong" do
        FileUtils.mkdir_p(tmp)
        json_path = File.join(tmp, "coverage.json")
        File.write(json_path, "{")

        expect(preparer.call(tmp))
          .to match(/\Acannot build index\.html from #{Regexp.escape(json_path)}: \S/)
      end
    end

    def preparer = described_class::Serve::ReportPreparer

    context "when the report preparer builds the index" do
      let(:formatter) { instance_double(SimpleCov::Formatter::HTMLFormatter) }
      let(:built) do
        allow(preparer).to receive(:require_relative)
        allow(SimpleCov::Formatter::HTMLFormatter).to receive(:new).and_return(formatter)
        allow(formatter).to receive(:format_from_json).and_return("report")
        preparer.send(:build_index, "cov/coverage.json", "cov")
      end

      it "reports nothing" do
        expect(built).to be_nil
      end

      it "loads the HTML formatter" do
        built

        expect(preparer).to have_received(:require_relative).with("../../formatter/html_formatter")
      end

      it "hands the JSON to it" do
        built

        expect(formatter).to have_received(:format_from_json).with("cov/coverage.json", "cov")
      end
    end

    context "with an invalid coverage.json" do
      let(:json_path) { File.join(tmp, "coverage.json") }

      before do
        FileUtils.mkdir_p(tmp)
        File.write(json_path, "{")
        allow(described_class).to receive(:coverage_dir).and_return(tmp)
        allow(TCPServer).to receive(:new).and_call_original
        exited!(1, run("serve"))
      end

      it "names itself" do
        expect(stderr.string).to start_with("simplecov serve:")
      end

      it "says what it could not do, and with what" do
        expect(stderr.string).to include("cannot build index.html").and include(json_path)
      end

      it "says it in one line" do
        expect(stderr.string.lines.size).to eq(1)
      end

      it "builds no index" do
        expect(File).not_to exist(File.join(tmp, "index.html"))
      end

      it "reports it before binding" do
        expect(TCPServer).not_to have_received(:new)
      end
    end

    def fake_client(request = "", timeout: true)
      klass = timeout ? fake_client_class : Class.new(fake_client_class) { undef_method(:timeout=) }
      klass.new(request)
    end

    describe "the accept loop" do
      it "says it is stopping when it is interrupted" do
        server = instance_double(TCPServer)
        allow(server).to receive(:accept).and_raise(Interrupt)
        out = StringIO.new

        described_class::Serve.send(:serve_loop, server, tmp, out)

        expect(out.string).to eq("\nsimplecov serve: stopping\n")
      end

      it "hands each accepted connection to the handler" do
        expect(connections_served).to contain_exactly([:first, tmp], [:second, tmp])
      end

      def connections_served
        server = instance_double(TCPServer)
        accepted = %i[first second]
        allow(server).to receive(:accept) { accepted.shift or raise Interrupt }
        served = Queue.new
        allow(described_class::Serve::StaticFileHandler)
          .to receive(:handle_connection) { |client, dir| served << [client, dir] }
        described_class::Serve.send(:serve_loop, server, tmp, StringIO.new)
        [served.pop, served.pop]
      end
    end

    describe "binding the socket" do
      it "answers what the block answered" do
        allow(TCPServer).to receive(:new).and_return(instance_double(TCPServer, close: nil))

        expect(described_class::Serve.send(:with_server, {host: "::1", port: 0}, StringIO.new) { 7 }).to eq(7)
      end

      it "closes the server when the block is done with it" do
        server = instance_double(TCPServer, close: nil)
        allow(TCPServer).to receive(:new).and_return(server)
        described_class::Serve.send(:with_server, {host: "::1", port: 0}, StringIO.new) { 7 }

        expect(server).to have_received(:close)
      end
    end

    context "when it cannot bind the socket" do
      let(:err) { StringIO.new }
      let(:status) do
        allow(TCPServer).to receive(:new).and_raise(Errno::EADDRINUSE)
        described_class::Serve.send(:with_server, {host: "127.0.0.1", port: 8080}, err) { 0 }
      end

      it "answers a failing status" do
        expect(status).to eq(1)
      end

      it "reports the host, the port, and what the system said" do
        status

        expect(err.string).to eq("simplecov serve: cannot bind to 127.0.0.1:8080 " \
                                 "(#{Errno::EADDRINUSE.new.message})\n")
      end
    end

    describe "announcing where it is listening" do
      def announce(addr)
        server = instance_double(TCPServer, addr: addr)
        out = StringIO.new
        described_class::Serve.send(:announce, out, server, "/srv/report")
        out.string
      end

      it "names the directory, the host, and the port it took" do
        expect(announce(["AF_INET", 8080, "localhost", "127.0.0.1"]))
          .to eq("simplecov serve: serving /srv/report at http://127.0.0.1:8080/\n" \
                 "Press Ctrl-C to stop.\n")
      end

      it "brackets an IPv6 address so the port is still a port" do
        expect(announce(["AF_INET6", 9292, "localhost", "::1"]))
          .to start_with("simplecov serve: serving /srv/report at http://[::1]:9292/\n")
      end

      it "leaves a name that is not an address alone" do
        expect(announce(["AF_INET", 3000, "example.test", "example.test"]))
          .to start_with("simplecov serve: serving /srv/report at http://example.test:3000/\n")
      end
    end

    describe "the options it takes" do
      def parse(*args)
        described_class::Serve.send(:parse, args)
      end

      it "asks the operating system for a port unless given one" do
        expect(parse).to eq(port: 0, host: "127.0.0.1")
      end

      it "takes a port as a number, not as the text it arrived as" do
        expect(parse("--port", "8080")).to eq(port: 8080, host: "127.0.0.1")
      end

      it "takes a host to bind to" do
        expect(parse("--host", "0.0.0.0")).to eq(port: 0, host: "0.0.0.0")
      end

      it "refuses a port that is not a number" do
        expect { parse("--port", "http") }.to raise_error(OptionParser::InvalidArgument)
      end
    end

    describe "reading one request off a connection" do
      let(:handler) { described_class::Serve::StaticFileHandler }

      before { File.write(File.join(tmp, "index.html"), "<html></html>") }

      it "gives an idle connection a deadline to finish its request" do
        client = fake_client("GET /index.html HTTP/1.1\r\nHost: x\r\n\r\n")

        handler.handle_connection(client, tmp)

        expect(client.read_timeout).to eq(described_class::Serve::StaticFileHandler::READ_TIMEOUT)
      end

      it "serves a connection that cannot be given a deadline" do
        client = fake_client("GET /index.html HTTP/1.1\r\nHost: x\r\n\r\n", timeout: false)

        handler.handle_connection(client, tmp)

        expect(client.written).to start_with("HTTP/1.1 200")
      end

      it "answers a request line missing its path with bad-request" do
        client = fake_client("GET\r\n\r\n")

        handler.handle_connection(client, tmp)

        expect(client.written).to start_with("HTTP/1.1 400")
      end

      it "leaves a route reading the body, not the headers" do
        seen = []
        routes = {"/events" => ->(client) { seen << client.readline }}
        client = fake_client("GET /events HTTP/1.1\r\nHost: x\r\n\r\nbody-line\n")

        handler.handle_connection(client, tmp, routes)

        expect(seen).to eq(["body-line\n"])
      end

      it "answers a request line missing its path exactly once" do
        client = fake_client("POST\r\n\r\n")

        handler.handle_connection(client, tmp)

        expect(client.written.scan("HTTP/1.1").size).to eq(1)
      end

      it "closes the connection, whatever the request was" do
        client = fake_client("GET /index.html HTTP/1.1\r\n\r\n")

        handler.handle_connection(client, tmp)

        expect(client.closed).to be true
      end

      it "closes quietly on a request that stops early" do
        client = fake_client("GET /index.html HTTP/1.1\r\n")
        handler.handle_connection(client, tmp)

        expect(client.closed).to be true
      end
    end

    describe "draining the headers" do
      let(:handler) { described_class::Serve::StaticFileHandler }

      it "reads to the blank line and stops there" do
        client = fake_client("Host: x\r\nAccept: */*\r\n\r\nbody-line\n")

        handler.send(:drain_headers, client)

        expect(client.readline).to eq("body-line\n")
      end

      it "stops on a blank line that carries nothing but its newline" do
        client = fake_client("\nafter\n")

        handler.send(:drain_headers, client)

        expect(client.readline).to eq("after\n")
      end
    end

    describe "the response it writes" do
      let(:handler) { described_class::Serve::StaticFileHandler }

      def respond(*args)
        client = fake_client
        handler.send(:respond, client, *args)
        client.written
      end

      {
        200 => "200 OK", 400 => "400 Bad Request", 403 => "403 Forbidden",
        404 => "404 Not Found", 405 => "405 Method Not Allowed"
      }.each do |status, line|
        it "names #{status} as #{line.inspect}" do
          expect(respond(status)).to start_with("HTTP/1.1 #{line}\r\n")
        end
      end

      it "answers a status it has no name for with one anyway" do
        expect(respond(418)).to start_with("HTTP/1.1 418 Error\r\n")
      end

      it "says the body is text unless told otherwise" do
        expect(respond(404)).to include("Content-Type: text/plain\r\n")
      end

      it "says what it was told otherwise" do
        expect(respond(200, "body", "text/css")).to include("Content-Type: text/css\r\n")
      end

      it "says bytes when it does not know what the body is" do
        expect(respond(200, "body", nil)).to include("Content-Type: application/octet-stream\r\n")
      end

      it "measures the body in bytes rather than characters" do
        expect(respond(200, "café")).to include("Content-Length: 5\r\n")
      end

      it "writes the whole head, then the body" do
        expect(respond(200, "hi", "text/plain"))
          .to eq("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n" \
                 "Content-Length: 2\r\nConnection: close\r\n\r\nhi")
      end
    end

    describe "what it serves, and what it refuses" do
      let(:handler) { described_class::Serve::StaticFileHandler }

      before do
        FileUtils.mkdir_p(File.join(tmp, "assets"))
        File.write(File.join(tmp, "index.html"), "<html></html>")
        File.write(File.join(tmp, "assets", "APP.JS"), "var x;")
        File.write(File.join(tmp, "assets", "data.bin"), "\x00\x01")
      end

      def serve(path)
        client = fake_client
        handler.send(:serve_file, client, path, tmp)
        client.written
      end

      it "answers a file with its own type, whatever case the name is in" do
        expect(serve("/assets/APP.JS")).to include("Content-Type: application/javascript\r\n")
      end

      it "answers a file it has no type for as bytes" do
        expect(serve("/assets/data.bin")).to include("Content-Type: application/octet-stream\r\n")
      end

      it "answers a missing file with not-found" do
        expect(serve("/missing.html")).to start_with("HTTP/1.1 404")
      end

      it "answers a traversal with forbidden" do
        expect(serve("/../secret.txt")).to start_with("HTTP/1.1 403")
      end

      it "answers the file's own bytes" do
        expect(serve("/index.html")).to end_with("<html></html>")
      end
    end

    describe "how it dispatches a request" do
      let(:handler) { described_class::Serve::StaticFileHandler }

      before { File.write(File.join(tmp, "index.html"), "<html></html>") }

      def dispatch(method, path, routes = {})
        client = fake_client
        handler.send(:dispatch, client, method, path, tmp, routes)
        client.written
      end

      %w[POST HEAD PUT].each do |method|
        it "answers #{method} with method-not-allowed, once" do
          expect(dispatch(method, "/")).to start_with("HTTP/1.1 405").and satisfy { |answer|
            answer.scan("HTTP/1.1").size == 1
          }
        end
      end

      it "answers nothing itself for a mounted path" do
        expect(dispatch("GET", "/events?since=3", "/events" => ->(client) { client })).to eq("")
      end

      it "hands the connection to its route, query string and all" do
        taken = []
        dispatch("GET", "/events?since=3", "/events" => ->(client) { taken << client })

        expect(taken.size).to eq(1)
      end

      it "serves a file for a path nothing is mounted on" do
        expect(dispatch("GET", "/index.html", {"/events" => ->(_) {}})).to start_with("HTTP/1.1 200")
      end
    end

    describe "what counts as inside the report directory" do
      let(:handler) { described_class::Serve::StaticFileHandler }

      it "counts the directory itself, however the two paths were built" do
        expect(handler.send(:inside?, File.join("/srv", "report"), "/srv/report")).to be true
      end

      it "counts a file within it" do
        expect(handler.send(:inside?, "/srv/report/index.html", "/srv/report")).to be true
      end

      it "counts out a sibling that starts with the same name" do
        expect(handler.send(:inside?, "/srv/report-secrets/x", "/srv/report")).to be false
      end

      it "counts out somewhere else entirely" do
        expect(handler.send(:inside?, "/etc/passwd", "/srv/report")).to be false
      end
    end

    describe ".resolve" do
      let(:handler) { described_class::Serve::StaticFileHandler }

      before do
        FileUtils.mkdir_p(File.join(tmp, "assets"))
        File.write(File.join(tmp, "index.html"), "<html></html>")
        File.write(File.join(tmp, "assets", "app.js"), "var x;")
      end

      it "maps `/` to index.html" do
        expect(handler.resolve("/", tmp)).to eq(File.realpath(File.join(tmp, "index.html")))
      end

      it "serves an explicit asset" do
        expect(handler.resolve("/assets/app.js", tmp))
          .to eq(File.realpath(File.join(tmp, "assets/app.js")))
      end

      it "strips query strings" do
        expect(handler.resolve("/index.html?_=1", tmp))
          .to eq(File.realpath(File.join(tmp, "index.html")))
      end

      it "maps a request with nothing in it at all to index.html" do
        expect(handler.resolve("", tmp)).to eq(File.realpath(File.join(tmp, "index.html")))
      end

      it "maps a bare query string to index.html" do
        expect(handler.resolve("/?_=1", tmp)).to eq(File.realpath(File.join(tmp, "index.html")))
      end

      it "keeps a question mark's worth of path and no more" do
        expect(handler.resolve("/index.html?a=1?b=2", tmp))
          .to eq(File.realpath(File.join(tmp, "index.html")))
      end

      it "refuses an absolute path outright" do
        expect(handler.resolve("//etc/passwd", tmp)).to eq(:forbidden)
      end

      it "returns nil for a directory that carries no index" do
        FileUtils.mkdir_p(File.join(tmp, "empty"))

        expect(handler.resolve("/empty", tmp)).to be_nil
      end

      it "returns nil for something that is neither a file nor a directory" do
        skip "no mkfifo on this platform" unless File.respond_to?(:mkfifo)
        File.mkfifo(File.join(tmp, "pipe"))

        expect(handler.resolve("/pipe", tmp)).to be_nil
      end

      it "returns nil for a file that vanishes mid-resolve" do
        vanishing = File.join(File.realpath(tmp), "index.html")
        allow(File).to receive(:realpath).and_call_original
        allow(File).to receive(:realpath).with(vanishing).and_raise(Errno::ENOENT)

        expect(handler.resolve("/index.html", tmp)).to be_nil
      end

      it "returns nil for a missing file" do
        expect(handler.resolve("/missing.html", tmp)).to be_nil
      end

      it "serves through a root that is itself a symlink" do
        link = File.join(Dir.mktmpdir("serve-link"), "docroot")
        File.symlink(File.realpath(tmp), link)

        expect(handler.resolve("/index.html", link)).to eq(File.realpath(File.join(tmp, "index.html")))
      end

      it "blocks parent-directory traversal" do
        expect(handler.resolve("/../secret.txt", tmp)).to eq(:forbidden)
      end

      it "maps a directory request to its index.html" do
        FileUtils.mkdir_p(File.join(tmp, "assets", "nested"))
        File.write(File.join(tmp, "assets", "nested", "index.html"), "ok")
        expect(handler.resolve("/assets/nested", tmp))
          .to eq(File.realpath(File.join(tmp, "assets/nested/index.html")))
      end

      it "blocks a symlink that escapes root" do
        Dir.mktmpdir("simplecov-cli-serve-escape-") do |outside|
          File.write(File.join(outside, "secret.txt"), "shhh")
          File.symlink(File.join(outside, "secret.txt"), File.join(tmp, "leak"))
          expect(handler.resolve("/leak", tmp)).to eq(:forbidden)
        end
      end
    end

    it "returns 403 for a path-traversal attempt" do
      expect(served_over_a_socket("GET /../secret.txt HTTP/1.1")).to start_with("HTTP/1.1 403")
    end

    # Serves one request over a real socket and answers the raw response.
    def served_over_a_socket(request_line, routes = {})
      FileUtils.mkdir_p(tmp)
      server = TCPServer.new("127.0.0.1", 0)
      thread = Thread.new do
        described_class::Serve::StaticFileHandler.handle_connection(server.accept, tmp, routes)
      end
      sock = TCPSocket.new("127.0.0.1", server.addr[1])
      sock.write("#{request_line}\r\nHost: x\r\n\r\n")
      sock.read
    ensure
      sock&.close
      thread&.join(2)
      server&.close
    end

    it "hands a matching path to its route" do
      File.write(File.join(tmp, "index.html"), "plain")

      expect(served_over_a_socket("GET /events?tab=1 HTTP/1.1", mounted_route)).to include("routed")
    end

    it "leaves the file tree to serve everything else" do
      FileUtils.mkdir_p(tmp)
      File.write(File.join(tmp, "index.html"), "plain")

      expect(served_over_a_socket("GET /index.html HTTP/1.1", mounted_route)).to include("plain")
    end

    def mounted_route
      handler = described_class::Serve::StaticFileHandler
      {"/events" => ->(client) { handler.respond(client, 200, "routed") }}
    end

    it "responds 400 to a malformed request line" do
      expect(served_over_a_socket("GET")).to start_with("HTTP/1.1 400")
    end

    it "brackets an IPv6 host in the announced URL" do
      expect(described_class::Serve.url_host("::1")).to eq("[::1]")
    end

    it "leaves an IPv4 host alone" do
      expect(described_class::Serve.url_host("127.0.0.1")).to eq("127.0.0.1")
    end

    it "exits 405 for non-GET requests" do
      expect(served_over_a_socket("POST / HTTP/1.1")).to start_with("HTTP/1.1 405")
    end

    it "rescues a misbehaving client without crashing" do
      expect { handle_a_closed_connection }.not_to raise_error
    end

    def handle_a_closed_connection
      FileUtils.mkdir_p(tmp)
      server = TCPServer.new("127.0.0.1", 0)
      Thread.new { TCPSocket.new("127.0.0.1", server.addr[1]).close }
      described_class::Serve::StaticFileHandler.handle_connection(server.accept, tmp)
    ensure
      server&.close
    end

    it "lets an exception out of its block" do
      allow(TCPServer).to receive(:new).and_return(instance_double(TCPServer, close: nil))

      expect { described_class::Serve.with_server({host: "127.0.0.1", port: 0}, stderr) { raise "boom" } }
        .to raise_error(RuntimeError, "boom")
    end

    it "closes a bound server when its block raises" do
      server = instance_double(TCPServer, close: nil)
      allow(TCPServer).to receive(:new).and_return(server)
      suppress(RuntimeError) { described_class::Serve.with_server({host: "127.0.0.1", port: 0}, stderr) { raise "boom" } }

      expect(server).to have_received(:close)
    end

    def announcing_url
      announced = Queue.new
      original = described_class::Serve.method(:announce)
      allow(described_class::Serve).to receive(:announce) do |out, server, dir|
        announced << "http://#{server.addr[3]}:#{server.addr[1]}/"
        original.call(out, server, dir)
      end
      announced
    end

    it "serves the report end-to-end through the run entry point" do
      expect(served_end_to_end).to match(end_to_end_answer)
    end

    def end_to_end_answer
      {index: ["200", a_string_including("via-run")], missing: "404", status: 0,
       announced: a_string_including("simplecov serve: serving #{tmp} at http://"), required_socket: true}
    end

    # Runs `serve` through the entry point against a live socket, answering
    # everything the example wants to know in one pass over the one server.
    def served_end_to_end
      File.write(File.join(tmp, "index.html"), "<html>via-run</html>")
      allow(described_class).to receive(:coverage_dir).and_return(tmp)
      announced = announcing_url
      allow(described_class::Serve).to receive(:require_socket).and_call_original
      thread = Thread.new { described_class.run(["serve"], stdout: stdout, stderr: stderr) }
      begin
        url = announced.pop
        index = Net::HTTP.get_response(URI(url))
        missing = Net::HTTP.get_response(URI("#{url}missing.html"))
      ensure
        thread.raise(Interrupt) if thread.alive?
        status = thread.join(2)&.value
      end
      {index: [index.code, index.body], missing: missing.code, status: status,
       announced: stdout.string, required_socket: socket_required?}
    end

    def socket_required?
      described_class::Serve.received_message?(:require_socket)
    rescue NoMethodError
      RSpec::Mocks.space.proxy_for(described_class::Serve).received_message?(:require_socket)
    end

    it "answers a request while another connection sits idle" do
      expect(answered_beside_an_idle_connection).to match(["200", a_string_including("concurrent")])
    end

    def answered_beside_an_idle_connection
      File.write(File.join(tmp, "index.html"), "<html>concurrent</html>")
      allow(described_class).to receive(:coverage_dir).and_return(tmp)
      announced = Queue.new
      allow(described_class::Serve).to receive(:announce) do |_stdout, server, _dir|
        announced << "http://#{server.addr[3]}:#{server.addr[1]}/"
      end
      thread = Thread.new { described_class.run(["serve"], stdout: stdout, stderr: stderr) }
      idle = nil
      begin
        uri = URI(announced.pop)
        idle = TCPSocket.new(uri.host, uri.port)
        response = Net::HTTP.get_response(uri)
        [response.code, response.body]
      ensure
        idle&.close
        thread.raise(Interrupt) if thread.alive?
        thread.join(2)
      end
    end
  end

  describe "clean subcommand", mutant_expression: "SimpleCov::CLI::Clean*" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-clean-spec-") }

    before do
      allow(described_class).to receive(:coverage_dir).and_return(tmp)
      FileUtils.mkdir_p(File.join(tmp, "assets"))
      File.write(File.join(tmp, "index.html"), "<html></html>")
      File.write(File.join(tmp, "coverage.json"), "{}")
    end

    after { FileUtils.rm_rf(tmp) }

    it "canonicalizes through symlinks, the way the targets it compares against are" do
      real = File.join(tmp, "real")
      link = File.join(tmp, "link")
      Dir.mkdir(real)
      File.symlink(real, link)

      expect(described_class::Clean.send(:canonical_path, link)).to eq(File.realpath(real))
    end

    it "still answers an absolute spelling for a path that is not there" do
      expect(described_class::Clean.send(:canonical_path, "no/such/dir"))
        .to eq(File.expand_path("no/such/dir"))
    end

    it "protects the working directory" do
      allow(described_class::Clean).to receive(:canonical_path).and_return("/canonical/cwd")

      expect(described_class::Clean.send(:protected_paths)).to eq(["/canonical/cwd"])
    end

    it "protects it by its canonical spelling" do
      allow(described_class::Clean).to receive(:canonical_path).and_return("/canonical/cwd")
      described_class::Clean.send(:protected_paths)

      expect(described_class::Clean).to have_received(:canonical_path).with(Dir.pwd)
    end

    it "removes the coverage directory" do
      run!("clean")

      expect(File).not_to exist(tmp)
    end

    it "reports what was deleted" do
      run!("clean")

      expect(stdout.string).to include("removed #{tmp}")
    end

    it "leaves disk untouched under --dry-run" do
      run!("clean", "--dry-run")

      expect(File).to exist(tmp)
    end

    it "reports what it would have deleted" do
      run!("clean", "--dry-run")

      expect(stdout.string).to include("would remove #{tmp}")
    end

    it "counts dotfiles in the --dry-run entry count" do
      File.write(File.join(tmp, ".resultset.json"), "{}")

      run!("clean", "--dry-run")

      expect(stdout.string).to include("(4 entries)")
    end

    it "is a no-op when the directory doesn't exist" do
      FileUtils.remove_entry(tmp)
      run!("clean")

      expect(stdout.string).to eq("simplecov clean: #{tmp} doesn't exist; nothing to do\n")
    end

    it "names the directory it removed, under the command's own name" do
      run!("clean")

      expect(stdout.string).to eq("simplecov clean: removed #{tmp}\n")
    end

    it "quotes the directory it refuses, so a stray space is visible" do
      Dir.chdir(tmp) do
        allow(described_class).to receive(:coverage_dir).and_return(".")
        exited!(1, run("clean"))

        expect(stderr.string).to eq(%(simplecov clean: refusing to remove unsafe coverage directory "."\n))
      end
    end

    it "removes a directory whose name prefixes the working directory's" do
      sibling = File.join(tmp, "coverage")
      clean_from_a_sibling_of(sibling)

      expect(File).not_to exist(sibling)
    end

    def clean_from_a_sibling_of(sibling)
      FileUtils.mkdir_p([sibling, File.join(tmp, "coverage-data")])
      Dir.chdir(File.join(tmp, "coverage-data")) do
        allow(described_class).to receive(:coverage_dir).and_return(sibling)
        run!("clean")
      end
    end

    it "still removes the directory under --quiet" do
      run!("clean", "--quiet")

      expect(File).not_to exist(tmp)
    end

    it "silences all status lines under --quiet" do
      run!("clean", "--quiet")

      expect(stdout.string).to be_empty
    end

    it "still leaves disk untouched under --dry-run --quiet" do
      run!("clean", "--dry-run", "--quiet")

      expect(File).to exist(tmp)
    end

    it "silences the --dry-run status line under --quiet" do
      run!("clean", "--dry-run", "--quiet")

      expect(stdout.string).to be_empty
    end

    it "silences the noop status line under --quiet" do
      FileUtils.remove_entry(tmp)
      run!("clean", "-q")

      expect(stdout.string).to be_empty
    end

    it "refuses to remove the current directory" do
      Dir.chdir(tmp) do
        allow(described_class).to receive(:coverage_dir).and_return(".")
        exited!(1, run("clean"))

        expect(File).to exist(File.join(tmp, "index.html"))
      end
    end

    it "says why it refused the current directory" do
      Dir.chdir(tmp) do
        allow(described_class).to receive(:coverage_dir).and_return(".")
        exited!(1, run("clean"))

        expect(stderr.string).to include("refusing to remove unsafe coverage directory")
      end
    end

    it "refuses to remove an ancestor of the current directory" do
      refuse_the_parent { expect(File).to exist(File.join(tmp, "index.html")) }
    end

    it "says why it refused the ancestor" do
      refuse_the_parent { expect(stderr.string).to include("refusing to remove unsafe coverage directory") }
    end

    def refuse_the_parent
      child = File.join(tmp, "nested")
      FileUtils.mkdir_p(child)
      Dir.chdir(child) do
        allow(described_class).to receive(:coverage_dir).and_return("..")
        exited!(1, run("clean", "--quiet"))
        yield
      end
    end

    it "refuses to remove the filesystem root" do
      allow(described_class).to receive(:coverage_dir).and_return(File::SEPARATOR)

      exited!(1, run("clean", "--dry-run"))

      expect(stderr.string).to include("refusing to remove unsafe coverage directory")
    end

    it "refuses to remove the project root found through .simplecov" do
      refuse_the_dotfile_root

      expect(File).to exist(File.join(tmp, "index.html"))
    end

    def refuse_the_dotfile_root
      File.write(File.join(tmp, ".simplecov"), "# project config\n")
      FileUtils.mkdir_p(File.join(tmp, "nested"))
      Dir.chdir(File.join(tmp, "nested")) do
        allow(described_class).to receive(:coverage_dir).and_return(tmp)
        exited!(1, run("clean"))
      end
    end
  end

  describe "open subcommand", mutant_expression: "SimpleCov::CLI::Open*" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-open-spec-") }

    after { FileUtils.remove_entry(tmp) }

    it "errors when the report file is missing, naming it" do
      missing = File.join(tmp, "missing.html")

      exited!(1, run("open", "--report", missing))

      expect(stderr.string).to eq("simplecov open: #{missing} not found\n")
    end

    it "opens the project's own report when told of no other" do
      expect(SimpleCov::CLI::Open.parse([])).to eq(described_class.default_report)
    end

    it "shells out to the platform opener with the report path" do
      report = File.join(tmp, "index.html")
      File.write(report, "<html></html>")
      allow(SimpleCov::CLI::Open).to receive_messages(browser_opener: ["open"], system: true)

      run!("open", "--report", report)

      expect(SimpleCov::CLI::Open).to have_received(:system).with("open", report)
    end

    it "errors when the platform has no known opener, naming the platform" do
      File.write(written_report, "<html></html>")
      allow(SimpleCov::CLI::Open).to receive(:browser_opener).and_return(nil)
      stub_const("RbConfig::CONFIG", RbConfig::CONFIG.merge("host_os" => "exotic-os"))
      exited!(1, run("open", "--report", written_report))

      expect(stderr.string).to eq("simplecov open: no known opener for exotic-os\n")
    end

    def written_report
      File.join(tmp, "index.html")
    end

    it "returns 1 when the opener exits non-zero" do
      report = File.join(tmp, "index.html")
      File.write(report, "<html></html>")
      allow(SimpleCov::CLI::Open).to receive_messages(browser_opener: ["open"], system: false)

      expect(run("open", "--report", report)).to eq(1)
    end

    it "routes through `cmd /c start` on Windows so cmd builtins resolve" do
      File.write(written_report, "<html></html>")
      stub_const("RbConfig::CONFIG", RbConfig::CONFIG.merge("host_os" => "mswin64"))
      allow(SimpleCov::CLI::Open).to receive(:system).and_return(true)
      run!("open", "--report", written_report)

      expect(SimpleCov::CLI::Open).to have_received(:system).with("cmd", "/c", "start", "", written_report)
    end

    describe ".browser_opener" do
      it "picks `open` on macOS" do
        stub_const("RbConfig::CONFIG", RbConfig::CONFIG.merge("host_os" => "darwin23"))
        expect(SimpleCov::CLI::Open.browser_opener).to eq(["open"])
      end

      %w[mswin64 mingw32 cygwin].each do |host|
        it "picks `cmd /c start` on #{host}" do
          stub_const("RbConfig::CONFIG", RbConfig::CONFIG.merge("host_os" => host))
          expect(SimpleCov::CLI::Open.browser_opener).to eq(["cmd", "/c", "start", ""])
        end
      end

      %w[linux-gnu freebsd14 solaris2.11].each do |host|
        it "picks `xdg-open` on #{host}" do
          stub_const("RbConfig::CONFIG", RbConfig::CONFIG.merge("host_os" => host))
          expect(SimpleCov::CLI::Open.browser_opener).to eq(["xdg-open"])
        end
      end

      it "returns nil for an unrecognized platform" do
        stub_const("RbConfig::CONFIG", RbConfig::CONFIG.merge("host_os" => "exotic-os"))
        expect(SimpleCov::CLI::Open.browser_opener).to be_nil
      end
    end
  end

  describe "colorizing subcommands in the standalone CLI process", mutant: false do
    let(:exe) { File.expand_path("../../exe/simplecov", __dir__) }
    let(:lib) { File.expand_path("../../lib", __dir__) }
    let(:filename) { "/project/app.rb" }

    around do |example|
      Dir.mktmpdir("simplecov-cli-standalone-spec-") do |dir|
        FileUtils.mkdir_p(File.join(dir, "coverage"))
        payload = {
          "total" => {"lines" => {"covered" => 8, "total" => 10, "percent" => 80.0}},
          "coverage" => {filename => {"total_lines" => 10, "covered_lines" => 5, "lines_covered_percent" => 50.0}},
          "groups" => {}
        }
        File.write(File.join(dir, "coverage", "coverage.json"), JSON.dump(payload))
        Dir.chdir(dir) { example.run }
      end
    end

    {
      "report" => [],
      "uncovered" => [],
      "coverage" => ["/project/app.rb"],
      "diff" => ["coverage/coverage.json"]
    }.each do |subcommand, extra_args|
      context "with `#{subcommand}`" do
        # Both examples read back the same invocation, and it is the spawn that
        # costs, so they share one.
        let(:captured) do
          CapturedRuns.once([:cli_standalone, subcommand]) do
            Open3.capture3(RbConfig.ruby, "-I", lib, exe, subcommand, *extra_args)
          end
        end

        it "runs without SimpleCov.color being loaded" do
          _stdout, stderr, status = captured

          expect(status).to be_success, stderr
        end

        it "reaches no undefined method along the way" do
          _stdout, stderr, = captured

          expect(stderr).not_to include("NoMethodError")
        end
      end
    end
  end
end
