# frozen_string_literal: true

require "coverage"
require "helper"
require "net/http"
require "open3"
require "simplecov/cli"
require "simplecov/production"
require "socket"
require "stringio"
require "support/git_fixture"
require "timeout"
require "tmpdir"

RSpec.describe SimpleCov::CLI do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }

  def run(*argv)
    described_class.run(argv, stdout: stdout, stderr: stderr)
  end

  # The --no-color kill-switch behaves identically across the read-only
  # subcommands; each colorization context supplies its argv.
  shared_examples "a --no-color subcommand" do
    it "skips colorization when --no-color is passed, even with Color.enabled? on" do
      allow(SimpleCov::Color).to receive(:enabled?).and_return(true)

      expect(run(*no_color_argv)).to eq(0)
      expect(stdout.string).not_to be_empty
      expect(stdout.string).not_to include("\e[")
    end
  end

  describe "dispatch", mutant_expression: ["SimpleCov::CLI#run", "SimpleCov::CLI#dispatch",
                                           "SimpleCov::CLI#usage", "SimpleCov::CLI#color_enabled?"] do
    it "prints usage and exits 0 with no arguments" do
      expect(run).to eq(0)
      expect(stdout.string).to include("Usage:")
    end

    it "prints usage on `help`" do
      expect(run("help")).to eq(0)
      expect(stdout.string).to include("Commands:")
    end

    it "prints usage on `--help`" do
      expect(run("--help")).to eq(0)
      expect(stdout.string).to include("Commands:")
    end

    it "prints usage on `-h`" do
      expect(run("-h")).to eq(0)
      expect(stdout.string).to include("Commands:")
    end

    it "complains and exits non-zero on an unknown command" do
      expect(run("nope")).to eq(1)
      expect(stderr.string).to include('unknown command "nope"')
    end

    it "shows what the commands are when it does not recognize the one it got" do
      run("nope")
      expect(stderr.string).to include("Commands:")
    end

    it "writes to the process's own streams when it is handed none" do
      expect { expect(described_class.run(["nope"])).to eq(1) }
        .to output(/unknown command "nope"/).to_stderr
      expect { expect(described_class.run(["help"])).to eq(0) }
        .to output(/Commands:/).to_stdout
    end

    it "prints the subcommand's own usage and exits 0 when the subcommand asks for it" do
      expect(run("uncovered", "--help")).to eq(0)
      expect(stdout.string).to include("Usage: simplecov uncovered")
    end

    it "hands the subcommand the very streams it was given" do
      handler = Class.new do
        def self.run(_rest, stdout:, stderr:)
          stdout.puts("handled")
          stderr.puts("noted")
          0
        end
      end
      stub_const("SimpleCov::CLI::COMMANDS", {"fake" => handler})

      expect(run("fake")).to eq(0)
      expect(stdout.string).to eq("handled\n")
      expect(stderr.string).to eq("noted\n")
    end

    it "is the full command list it hands out as usage" do
      expect(described_class.usage).to include("Usage:").and include("Commands:")
    end

    it "colorizes nothing when --no-color was passed, whatever the stream would allow" do
      allow(SimpleCov::Color).to receive(:enabled?).and_return(true)

      expect(described_class.color_enabled?({no_color: true}, stdout)).to be(false)
    end

    it "defers to Color when --no-color was given as false rather than omitted" do
      allow(SimpleCov::Color).to receive(:enabled?).and_return(true)

      expect(described_class.color_enabled?({no_color: false}, stdout)).to be(true)
    end

    it "asks Color about the very stream it was given when --no-color was not passed" do
      allow(SimpleCov::Color).to receive(:enabled?).and_return(true)

      expect(described_class.color_enabled?({}, stdout)).to be(true)
      expect(SimpleCov::Color).to have_received(:enabled?).with(stdout)
    end

    it "reports an unknown option as a one-line error" do
      expect(run("uncovered", "--bogus")).to eq(1)
      expect(stderr.string).to eq("simplecov uncovered: invalid option: --bogus (run `simplecov help` for usage)\n")
    end

    it "reports a malformed typed argument as a one-line error" do
      expect(run("serve", "--port", "foo")).to eq(1)
      expect(stderr.string).to eq("simplecov serve: invalid argument: --port foo (run `simplecov help` for usage)\n")
    end
  end

  describe SimpleCov::CLI::Git, mutant_expression: "SimpleCov::CLI::Git*" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-git-spec-") }

    after { FileUtils.rm_rf(tmp) }

    def repo!(branch)
      GitFixture.init_repo(tmp, branch: branch)
      system("git", "-C", tmp, "commit", "-q", "--allow-empty", "-m", "init", exception: true)
    end

    describe ".capture" do
      # git reports failures over several lines; the caller wants one
      # line of it, without the newline it came with.
      it "answers the first line of git's complaint, trimmed" do
        allow(Open3).to receive(:capture3).and_return(
          ["", "  fatal: not a thing  \nhint: try something else\n", instance_double(Process::Status, success?: false)]
        )

        _stdout, detail, success = described_class.capture("rev-parse", "--nope")
        expect(detail).to eq("fatal: not a thing")
        expect(success).to be(false)
      end

      # git missing from PATH is not a git error, so the run reads as
      # unsuccessful with nothing on stdout and the reason as detail.
      it "reads a spawn failure as an unsuccessful run carrying the message" do
        allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT, "git")

        stdout, detail, success = described_class.capture("status")
        expect(stdout).to be_nil
        expect(detail).to include("git")
        expect(success).to be(false)
      end

      it "answers nothing said when git said nothing" do
        allow(Open3).to receive(:capture3).and_return(["out\n", "", instance_double(Process::Status, success?: true)])

        expect(described_class.capture("rev-parse", "HEAD")).to eq(["out\n", "", true])
      end
    end

    describe ".toplevel" do
      it "answers the working tree's root, without the newline git adds" do
        repo!("main")
        expect(Dir.chdir(tmp) { described_class.toplevel }).to eq(File.realpath(tmp))
      end

      it "answers nothing outside a working tree" do
        allow(described_class).to receive(:capture).and_return(["", "fatal: not a git repository", false])
        expect(described_class.toplevel).to be_nil
      end
    end

    describe ".default_base" do
      it "resolves the branch origin's HEAD points at" do
        repo!("trunk")
        system("git", "-C", tmp, "update-ref", "refs/remotes/origin/trunk", "HEAD", exception: true)
        system("git", "-C", tmp, "symbolic-ref", "refs/remotes/origin/HEAD",
               "refs/remotes/origin/trunk", exception: true)

        expect(Dir.chdir(tmp) { described_class.default_base }).to eq("trunk")
      end

      it "falls back to main when no origin HEAD is recorded" do
        repo!("main")
        expect(Dir.chdir(tmp) { described_class.default_base }).to eq("main")
      end
    end

    describe ".option_like_ref?" do
      it "flags refs git would parse as options" do
        expect(described_class.option_like_ref?("--output=x")).to be(true)
        expect(described_class.option_like_ref?("main")).to be(false)
      end
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
      # Each unit changes over at an exact second, and the boundary
      # belongs to the larger unit. Tested on both sides of all three.
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

    it "names itself in the error when the report cannot be read" do
      expect(run("status", "--input", File.join(tmp, "absent.json"))).to eq(1)
      expect(stderr.string).to start_with("simplecov status:")
    end

    it "reports the report's age, run, and commit distance" do
      first_commit = write_stale_fixture

      expect(run_status).to eq(0)
      expect(stdout.string).to include("report #{json_path}")
      expect(stdout.string).to include("generated").and include("(2 minutes ago)")
      expect(stdout.string).to include("by simplecov 9.9.9 running RSpec")
      expect(stdout.string).to include("commit #{first_commit[0, 7]} (1 commit behind HEAD)")
    end

    it "reports totals, the recorded tests, and the resultset's entries" do
      write_stale_fixture

      expect(run_status).to eq(0)
      expect(stdout.string).to include("line 92.50%, branch 88.00%")
      expect(stdout.string).to include("tests recorded: 2 (track_tests)")
      expect(stdout.string).to include("resultset #{resultset_path}")
      expect(stdout.string).to include("RSpec: 5 minutes ago")
    end

    it "reads a report at the current HEAD as current" do
      repo!
      head = Dir.chdir(tmp) { `git rev-parse HEAD`.strip }
      write_report(commit: head)

      expect(run_status).to eq(0)
      expect(stdout.string).to include("commit #{head[0, 7]} (current HEAD)")
    end

    it "degrades when the report records no commit and no git is around" do
      write_report

      expect(run_status).to eq(0)
      expect(stdout.string).to include("commit not recorded")
      expect(stdout.string).to include("tests recorded: none (enable track_tests")
      expect(stdout.string).to include("resultset none")
    end

    it "marks a commit outside this repository's history" do
      repo!
      write_report(commit: "0" * 40)

      expect(run_status).to eq(0)
      expect(stdout.string).to include("(not in this repository's history)")
    end

    it "counts plural commits behind" do
      repo!
      system("git", "-C", tmp, "-c", "user.email=spec@example.com", "-c", "user.name=spec",
             "commit", "-q", "--allow-empty", "-m", "c2", exception: true)
      first_commit = Dir.chdir(tmp) { `git rev-parse HEAD~2`.strip }
      write_report(commit: first_commit)

      expect(run_status).to eq(0)
      expect(stdout.string).to include("(2 commits behind HEAD)")
    end

    it "degrades around a minimal document and malformed resultset entries" do
      File.write(json_path, JSON.dump({}))
      File.write(resultset_path, JSON.dump("Broken" => "junk", "NoStamp" => {"coverage" => {}}))

      expect(run_status).to eq(0)
      expect(stdout.string).to include("commit not recorded")
      expect(stdout.string).to include("Broken: age unknown").and include("NoStamp: age unknown")
      expect(stdout.string).not_to include("generated")
    end

    it "shrugs at an unparseable timestamp and a non-object resultset" do
      write_report
      document = JSON.parse(File.read(json_path))
      document["meta"]["timestamp"] = "junk"
      File.write(json_path, JSON.dump(document))
      File.write(resultset_path, "[]")

      expect(run_status).to eq(0)
      expect(stdout.string).to include("generated junk\n")
      expect(stdout.string).to include("resultset none")
    end

    it "emits the same facts as JSON" do
      repo!
      head = Dir.chdir(tmp) { `git rev-parse HEAD`.strip }
      write_report(commit: head, contexts: ["spec/a_spec.rb:1"])

      expect(run_status("--json")).to eq(0)
      parsed = JSON.parse(stdout.string)
      expect(parsed["commit"]).to eq(head)
      expect(parsed["behind"]).to eq(0)
      expect(parsed["contexts"]).to eq(1)
      expect(parsed["totals"]).to eq("line" => 92.5, "branch" => 88.0)
    end

    it "errors like every reader when the report is missing" do
      expect(run_status).to eq(1)
      expect(stderr.string).to include("not found")
    end

    it "documents itself in the usage text" do
      expect(run("help")).to eq(0)
      expect(stdout.string).to include("status")
    end

    it "speaks ages in sensible units" do
      words = described_class::Status.method(:age_in_words)
      expect(words.call(45)).to eq("45 seconds")
      expect(words.call(600)).to eq("10 minutes")
      expect(words.call(7200)).to eq("2 hours")
      expect(words.call(200_000)).to eq("2 days")
    end
  end

  # The plumbing every read-only subcommand extends. Exercised through
  # a stand-in module rather than through one of the nine commands, so
  # what is under test is the helper itself and not a caller's use of it.
  describe SimpleCov::CLI::CommandHelpers, mutant_expression: "SimpleCov::CLI::CommandHelpers*" do
    let(:host) do
      Module.new do
        def self.name = "SimpleCov::CLI::Pretend"
        extend SimpleCov::CLI::CommandHelpers
      end
    end

    describe ".build_parser" do
      it "wires --help into every parser it builds" do
        expect { host.build_parser.parse(["--help"]) }
          .to raise_error(SimpleCov::CLI::CommandHelpers::HelpRequested)
      end

      it "answers -h the same way" do
        expect { host.build_parser.parse(["-h"]) }
          .to raise_error(SimpleCov::CLI::CommandHelpers::HelpRequested)
      end

      it "yields the parser it is building to the command's own options" do
        seen = nil

        parser = host.build_parser { |own| seen = own }

        expect(seen).to be(parser)
      end

      it "builds a parser for a command with no options of its own" do
        expect(host.build_parser).to be_a(OptionParser)
      end
    end

    describe ".quiet_option" do
      it "declares the long form and its short alias, both setting :quiet" do
        opts = {quiet: false}
        parser = host.build_parser { |own| host.quiet_option(own, opts) }

        parser.parse(["--quiet"])

        expect(opts).to eq(quiet: true)
      end
    end

    describe ".one?" do
      subject(:helpers) { Module.new { extend SimpleCov::CLI::CommandHelpers } }

      it "is true only for exactly one" do
        expect(helpers.one?(1)).to be(true)
      end

      it "is false for none" do
        expect(helpers.one?(0)).to be(false)
      end

      it "is false for several" do
        expect(helpers.one?(2)).to be(false)
      end
    end

    describe "#on_help" do
      # Both spellings, because dropping either leaves optparse's own
      # officious handler, which prints a summary and exits the process
      # from inside the parser rather than failing anything observable.
      ["--help", "-h"].each do |flag|
        it "raises HelpRequested for #{flag}" do
          parser = host.build_parser
          expect { parser.parse([flag]) }
            .to raise_error(SimpleCov::CLI::CommandHelpers::HelpRequested)
        end
      end
    end

    describe "#command_name" do
      it "names the command after the last segment of the module, downcased" do
        expect(host.command_name).to eq("pretend")
      end
    end

    describe "#parse_common" do
      it "seeds the shared defaults" do
        opts, = host.parse_common([])
        expect(opts).to eq(input: SimpleCov::CLI.default_input, json: false, no_color: false)
      end

      it "lets a command's own defaults join the shared ones" do
        opts, = host.parse_common([], threshold: 2.5)
        expect(opts).to include(threshold: 2.5, json: false)
      end

      it "returns the positional arguments after the flags, in order" do
        _opts, rest = host.parse_common(["--json", "first", "second"])
        expect(rest).to eq(%w[first second])
      end

      it "reads the shared trio" do
        opts, = host.parse_common(["--input", "cov.json", "--json", "--no-color"])
        expect(opts).to include(input: "cov.json", json: true, no_color: true)
      end

      it "yields the parser and the options so a command can add its own" do
        seen = nil
        opts, = host.parse_common(["--only-mine"]) do |parser, options|
          seen = options
          parser.on("--only-mine") { options[:mine] = true }
        end

        expect(opts).to include(mine: true)
        expect(seen).to be(opts)
      end
    end

    describe "#stats_row" do
      it "labels, aligns and counts the row" do
        expect(host.stats_row("lines", "80.00%", 8, 10)).to eq("  lines:  80.00% (8 / 10)")
      end

      # `to_i` reads what it can and stops; a stricter conversion would
      # raise on the same input, and formatting the raw value would too.
      it "reads a count that carries trailing text" do
        expect(host.stats_row("branches", "50.00%", "3 of them", "6 total")).to eq("  branches: 50.00% (3 / 6)")
      end
    end

    describe "#recorded_contexts" do
      let(:stderr) { StringIO.new }

      it "answers the recorded contexts" do
        contexts = %w[a_spec.rb:1 b_spec.rb:2]
        expect(host.recorded_contexts({"contexts" => contexts}, {input: "cov.json"}, stderr)).to eq(contexts)
      end

      it "points at the switch when nothing was recorded" do
        expect(host.recorded_contexts({}, {input: "cov.json"}, stderr)).to be_nil
        expect(stderr.string).to include("no test contexts recorded in cov.json")
          .and include("track_tests")
      end

      it "rejects a context list that is not strings" do
        expect(host.recorded_contexts({"contexts" => [1, 2]}, {input: "cov.json"}, stderr)).to be_nil
        expect(stderr.string).to include('"contexts" must be an array of strings')
      end

      it "rejects contexts that are not a list at all" do
        expect(host.recorded_contexts({"contexts" => "a_spec.rb"}, {input: "cov.json"}, stderr)).to be_nil
        expect(stderr.string).to include('"contexts" must be an array of strings')
      end
    end
  end

  # The freshness facts, read straight rather than through the
  # subcommand: what these answer for a well-formed report is already
  # covered there, and what they answer for a malformed one is the part
  # a fixture written by hand can reach.
  describe SimpleCov::CLI::Status::Facts, mutant_expression: "SimpleCov::CLI::Status::Facts*" do
    subject(:facts) { described_class }

    describe "#age_of" do
      it "answers whole seconds between the wall clock and the stored epoch" do
        allow(Process).to receive(:clock_gettime).and_return(500.9)

        expect(facts.send(:age_of, 100)).to be(400)
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

      it "answers nil for a commit that is not a string, without asking git" do
        allow(SimpleCov::CLI::Git).to receive(:capture)

        expect(facts.behind(12_345)).to be_nil
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
      it "answers empty facts for meta that is not an object" do
        expect(facts.meta_facts("meta" => [])).to eq(
          generated_at: nil, age: nil, version: nil, command_name: nil, commit: nil, behind: nil
        )
      end

      # Whole hash: every fact is read from its own key, and a fact that
      # went missing or arrived under another name would otherwise pass.
      it "reads each fact from the metadata it was written under" do
        generated = Time.now - 12.6
        allow(SimpleCov::CLI::Git).to receive(:capture).and_return(["4\n", "", true])

        expect(facts.meta_facts("meta" => {"timestamp" => generated.iso8601(3),
                                           "simplecov_version" => "9.9.9",
                                           "command_name" => "RSpec",
                                           "commit" => "abc1234"})).to eq(
                                             generated_at: generated.iso8601(3), age: 12,
                                             version: "9.9.9", command_name: "RSpec",
                                             commit: "abc1234", behind: 4
                                           )
      end
    end

    describe "#gather" do
      it "counts the recorded contexts, and says where the resultset was sought" do
        answered = facts.gather({"contexts" => %w[a b c]}, "/nonexistent/.resultset.json")
        expect(answered).to eq(
          generated_at: nil, age: nil, version: nil, command_name: nil, commit: nil, behind: nil,
          totals: {}, contexts: 3,
          resultset_path: "/nonexistent/.resultset.json", resultset: nil
        )
      end

      # Reads the totals out of the report and the entries out of the
      # resultset beside it, each from its own place.
      it "gathers the totals and the resultset together" do
        dir = Dir.mktmpdir("simplecov-gather-spec-")
        path = File.join(dir, ".resultset.json")
        File.write(path, JSON.dump("RSpec" => {"timestamp" => (Time.now - 60).to_i}))

        answered = facts.gather({"total" => {"lines" => {"percent" => 92.5}}}, path)
        expect(answered).to include(totals: {"line" => 92.5}, contexts: nil,
                                    resultset_path: path, resultset: [{command: "RSpec", age: 60}])
      ensure
        FileUtils.remove_entry(dir)
      end

      it "answers no count for a report that recorded no contexts at all" do
        expect(facts.gather({}, "/nonexistent/.resultset.json")[:contexts]).to be_nil
      end

      it "answers no count for contexts that are not a list" do
        answered = facts.gather({"contexts" => "a_spec.rb"}, "/nonexistent/.resultset.json")
        expect(answered[:contexts]).to be_nil
      end
    end

    describe "#resultset" do
      let(:path) { File.join(dir, ".resultset.json") }
      let(:dir) { Dir.mktmpdir("simplecov-facts-spec-") }

      after { FileUtils.remove_entry(dir) }

      it "ages each command against the time it recorded" do
        File.write(path, JSON.dump("RSpec" => {"timestamp" => (Time.now - 300).to_i}))
        expect(facts.resultset(path)).to eq([{command: "RSpec", age: 300}])
      end

      it "answers no age for an entry that carries no timestamp" do
        File.write(path, JSON.dump("RSpec" => {"coverage" => {}}))
        expect(facts.resultset(path)).to eq([{command: "RSpec", age: nil}])
      end

      it "answers no age for a timestamp that is not a number" do
        File.write(path, JSON.dump("RSpec" => {"timestamp" => "recently"}))
        expect(facts.resultset(path)).to eq([{command: "RSpec", age: nil}])
      end

      it "answers no age for an entry that is not an object" do
        File.write(path, JSON.dump("RSpec" => []))
        expect(facts.resultset(path)).to eq([{command: "RSpec", age: nil}])
      end

      it "answers nil when the resultset is not there" do
        expect(facts.resultset(File.join(dir, "absent.json"))).to be_nil
      end

      it "answers nil when the resultset is not JSON" do
        File.write(path, "not json")
        expect(facts.resultset(path)).to be_nil
      end

      it "answers nil when the resultset is not an object" do
        File.write(path, JSON.dump([1, 2]))
        expect(facts.resultset(path)).to be_nil
      end
    end
  end

  describe "badge subcommand", mutant_expression: "SimpleCov::CLI::Badge*" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-badge-spec-") }
    let(:json_path) { File.join(tmp, "coverage.json") }
    # Asserted whole rather than by fragments: the badge is one rendered
    # artifact, every number in it is derived from the two segment
    # widths, and a fragment assertion leaves the rest of the document
    # free to drift. This is the reference rendering the geometry
    # examples below take apart.
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

    it "prints the whole flat SVG badge for a known percent" do
      write_report(line: 92.5)

      expect(run_badge).to eq(0)
      expect(stdout.string).to eq(reference_badge)
    end

    # The geometry the document lays out: two segments sized by their
    # own text, and text coordinates in the 10x space the scale(.1)
    # trick draws in.
    describe "geometry" do
      let(:svg) { described_class::Badge::Svg }

      it "sizes a segment by its text, with padding on both sides" do
        expect(svg.width("")).to eq(10)
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

    it "follows the chosen criterion and colors the lower rungs" do
      write_report(line: 92.5, branch: 55.0)

      expect(run_badge("--criterion", "branch")).to eq(0)
      expect(stdout.string).to include('aria-label="branch coverage: 55.00%"').and include('fill="#fe7d37"')
    end

    it "steps through the whole color ladder" do
      colors = [95, 85, 75, 65, 55, 45].collect { |pct| described_class::Badge::Svg.color(pct) }
      expect(colors).to eq(["#4c1", "#97ca00", "#a4a61d", "#dfb317", "#fe7d37", "#e05d44"])
    end

    # Each rung's own number belongs to that rung, not the one below:
    # exactly 90% is bright green, not the 80s' colour.
    it "gives each rung's boundary to the rung it names" do
      colors = [90, 80, 70, 60, 50].collect { |pct| described_class::Badge::Svg.color(pct) }
      expect(colors).to eq(["#4c1", "#97ca00", "#a4a61d", "#dfb317", "#fe7d37"])
    end

    it "answers its own usage for --help" do
      expect(run("badge", "--help")).to eq(0)
      expect(stdout.string).to include("badge options:").and include("--criterion")
    end

    # The shared handler is what makes that work: it raises for the
    # dispatcher to answer, where optparse's own officious --help would
    # print a bare summary and exit the process from inside the parser.
    # Caught explicitly, including SystemExit, so the officious handler
    # is compared against rather than allowed to end the run.
    it "wires the shared help handler rather than leaving optparse's" do
      raised = nil
      begin
        described_class::Badge.parse(["--help"])
      rescue Exception => e # rubocop:disable Lint/RescueException
        raised = e
      end

      expect(raised).to be_a(SimpleCov::CLI::CommandHelpers::HelpRequested)
    end

    # Without --input the badge reads the project's own report, the way
    # every other read-only command defaults its path. The discovered
    # directory is memoized on the CLI, so it is reset around this
    # example the way `.coverage_dir`'s own examples reset it.
    it "reads the default report when given no input path" do
      previous = described_class.instance_variable_get(:@coverage_dir)
      described_class.instance_variable_set(:@coverage_dir, nil)
      Dir.mktmpdir("simplecov-cli-badge-default-") do |dir|
        FileUtils.mkdir_p(File.join(dir, "coverage"))
        File.write(File.join(dir, "coverage", "coverage.json"),
                   JSON.dump("meta" => {}, "total" => {"lines" => {"percent" => 92.5}}))
        Dir.chdir(dir) do
          expect(run("badge")).to eq(0)
          expect(stdout.string).to include('aria-label="line coverage: 92.50%"')
        end
      end
    ensure
      described_class.instance_variable_set(:@coverage_dir, previous)
    end

    it "writes the badge to a file with --output and stays quiet" do
      write_report
      target = File.join(tmp, "badge.svg")

      expect(run_badge("--output", target)).to eq(0)
      expect(File.read(target)).to include(">92.50%</text>")
      expect(stdout.string).to be_empty
    end

    it "renames the label and escapes markup in it" do
      write_report

      expect(run_badge("--label", "lines <&> \"covered\"")).to eq(0)
      expect(stdout.string).to include(">lines &lt;&amp;&gt; &quot;covered&quot;</text>")
    end

    it "errors on an unknown criterion" do
      write_report

      expect(run_badge("--criterion", "files")).to eq(1)
      expect(stderr.string).to eq("simplecov badge: unknown --criterion :files (expected line, branch, or method)\n")
    end

    it "errors when the report carries no totals at all" do
      File.write(json_path, JSON.dump("meta" => {}))

      expect(run_badge).to eq(1)
      expect(stderr.string).to include("no line totals in #{json_path}")
    end

    it "errors when the report has no totals for the criterion" do
      write_report(line: 92.5)

      expect(run_badge("--criterion", "branch")).to eq(1)
      expect(stderr.string).to include("no branch totals in #{json_path}")
    end

    it "errors when the report is missing, under its own command name" do
      expect(run_badge).to eq(1)
      expect(stderr.string).to eq("simplecov badge: #{json_path} not found\n")
    end

    # A percent the report carries as something other than a number is
    # no percent at all, and saying so beats rendering nonsense.
    it "errors when the recorded percent is not a number" do
      File.write(json_path, JSON.dump("meta" => {}, "total" => {"lines" => {"percent" => "92.5"}}))

      expect(run_badge).to eq(1)
      expect(stderr.string).to include("no line totals in #{json_path}")
    end

    it "errors when the totals section is not an object at all" do
      File.write(json_path, JSON.dump("meta" => {}, "total" => "junk"))

      expect(run_badge).to eq(1)
      expect(stderr.string).to include("no line totals in #{json_path}")
    end

    # Any Hash of totals will do, including one a document reader hands
    # back as a subclass of it.
    it "reads a totals section that arrives as a Hash subclass" do
      totals = Class.new(Hash).new.merge!("lines" => {"percent" => 92.5})
      allow(SimpleCov::CLI::CoverageFile).to receive(:load_document).and_return({"total" => totals})

      expect(run_badge).to eq(0)
      expect(stdout.string).to include('aria-label="line coverage: 92.50%"')
    end

    it "passes xmllint's validation" do
      skip "xmllint is not installed here" unless system("xmllint", "--version", out: File::NULL, err: File::NULL)

      write_report
      expect(run_badge).to eq(0)
      file = File.join(tmp, "badge.svg")
      File.write(file, stdout.string)
      expect(system("xmllint", "--noout", file)).to be(true)
    end
  end

  describe "completions subcommand", mutant_expression: "SimpleCov::CLI::Completions*" do
    def shell_available?(shell)
      system(shell, "-c", "true", out: File::NULL, err: File::NULL)
    end

    def generate(shell)
      expect(run("completions", shell)).to eq(0)
      stdout.string
    end

    it "errors without a shell, once" do
      expect(run("completions")).to eq(1)
      expect(stderr.string).to eq("simplecov completions: missing shell (expected fish, bash, or zsh)\n")
    end

    it "errors on an unknown shell" do
      expect(run("completions", "tcsh")).to eq(1)
      expect(stderr.string).to eq("simplecov completions: unknown shell \"tcsh\" (expected fish, bash, or zsh)\n")
    end

    # The arguments go through a parser rather than straight to the
    # shell name, which is what gives the command its own --help.
    it "answers its own usage for --help" do
      expect(run("completions", "--help")).to eq(0)
      expect(stdout.string).to include("completions <shell>")
    end

    it "generates fish completions from the usage document" do
      out = generate("fish")
      expect(out).to include("complete -c simplecov -f -n __fish_use_subcommand -a affected")
      expect(out).to include("__fish_seen_subcommand_from affected")
      expect(out).to include("-l base -r")
      expect(out).to include("-s q -l quiet")
      expect(out).to include("-a 'fish bash zsh'")
      expect(out).to include("-l help")
    end

    it "generates bash completions" do
      out = generate("bash")
      expect(out).to include("_simplecov()")
      expect(out).to include("complete -o default -F _simplecov simplecov")
      expect(out).to match(/affected\)\s+opts="[^"]*--base/)
      expect(out).to include('compgen -W "fish bash zsh -h --help"')
    end

    it "generates zsh completions" do
      out = generate("zsh")
      expect(out).to include("#compdef simplecov")
      expect(out).to include("_describe")
      expect(out).to include("'--base=[")
      expect(out).to include("'1:shell:(fish bash zsh)'")
    end

    # The three renderers take the same parsed usage data and each turn
    # it into a whole script, so they are asserted whole against a small
    # fixture: two commands, an option with a short form, one that takes
    # an argument, and the completions command whose shell argument the
    # usage tables cannot carry. A fragment assertion would leave most
    # of each template free to drift.
    describe "the rendered scripts" do
      let(:scripts) { described_class::Completions::Scripts }
      # "completions" is deliberately first, and its name built at
      # runtime rather than written as a literal: the renderers skip
      # that command by name, so a skip that stopped the walk would lose
      # the command behind it, and an identity comparison would never
      # recognise a name the usage document was parsed into.
      let(:completions_name) { +"completions" }
      let(:commands) { [["report", "Print the summary"], [completions_name, "Emit the script"]] }
      let(:options) do
        {completions_name => [{short: nil, long: "--input", arg: "PATH", desc: "Read from PATH"}],
         "report" => [{short: nil, long: "--json", arg: nil, desc: "Emit JSON"},
                      {short: "-q", long: "--quiet", arg: nil, desc: "Say nothing"}]}
      end

      it "renders the whole fish script" do
        expect(scripts.fish(commands, options)).to eq(<<~FISH.chomp)
          # Completions for simplecov. Generated by `simplecov completions fish`.
          complete -c simplecov -f -n __fish_use_subcommand -a report -d 'Print the summary'
          complete -c simplecov -f -n __fish_use_subcommand -a completions -d 'Emit the script'
          complete -c simplecov -n '__fish_seen_subcommand_from completions' -l input -r -d 'Read from PATH'
          complete -c simplecov -n '__fish_seen_subcommand_from report' -l json -d 'Emit JSON'
          complete -c simplecov -n '__fish_seen_subcommand_from report' -s q -l quiet -d 'Say nothing'
          complete -c simplecov -f -n '__fish_seen_subcommand_from completions' -a 'fish bash zsh'
        FISH
      end

      it "renders the whole bash script" do
        expect(scripts.bash(commands, options)).to eq(<<~BASH.chomp)
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

      it "renders the whole zsh script" do
        expect(scripts.zsh(commands, options)).to eq(<<~ZSH.chomp)
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

      # Each shell quotes its descriptions its own way, and a
      # description carrying the quote character is the case that
      # decides whether a generated script parses at all.
      it "escapes every quote and backslash for fish, not just the first" do
        expect(scripts.fish_quote(%q(a \ b \ c))).to eq("'a \\\\ b \\\\ c'")
        expect(scripts.fish_quote("it's o'clock")).to eq(%q('it\'s o\'clock'))
      end

      it "escapes quotes for zsh by closing, quoting, and reopening" do
        expect(scripts.zsh_quote("it's here")).to eq("it'\\''s here")
      end

      # Brackets delimit a zsh description, so one inside would end it
      # early; they are dropped rather than escaped.
      it "drops brackets from a zsh description" do
        expect(scripts.zsh_specs(short: nil, long: "--x", arg: nil, desc: "a [bracketed] note"))
          .to eq(["'--x[a bracketed note]'"])
      end
    end

    # The other half of the command: reading the usage document back
    # into the command and option tables the renderers above consume.
    describe "the parsed usage" do
      let(:completions) { described_class::Completions }

      it "reads each command row as its name and its description" do
        expect(completions.commands.first).to eq(["run", "Execute <command> with SimpleCov pre-loaded"])
      end

      it "keeps the table's own header and wrapped continuations out of the commands" do
        names = completions.commands.collect(&:first)
        expect(names).to include("badge", "completions", "help")
        expect(names).not_to include("Commands:", "(works")
      end

      it "gives a command only the options of its own sections" do
        longs = completions.options_for("badge").collect { |option| option[:long] }
        expect(longs).to include("--output", "--criterion", "--label")
        expect(longs).not_to include("--threshold", "--fail-on-drop")
      end

      it "reads a switch's short form, argument, and description together" do
        expect(completions.options_for("merge").detect { |option| option[:long] == "--quiet" })
          .to eq(short: "-q", long: "--quiet", arg: nil, desc: "Suppress the success status line")
        expect(completions.options_for("badge").detect { |option| option[:long] == "--output" })
          .to include(short: nil, arg: "PATH")
      end

      it "offers every command its own --help, with the short form too" do
        expect(completions.options_for("badge").last)
          .to eq(short: "-h", long: "--help", arg: nil, desc: "Show this command's usage")
      end

      # Everything after `run` belongs to the command being run, so it
      # offers nothing of its own and drops out of the table entirely.
      it "leaves run without options, and out of the option table" do
        expect(completions.options_for("run")).to eq([])
        expect(completions.options_by_command).not_to have_key("run")
        expect(completions.options_by_command).to be_a(Hash)
      end

      it "folds a wrapped description onto the option it belongs to, not the first one" do
        section = ["clean options:",
                   "  --dry-run                 Print what would",
                   "                            be removed",
                   "  -q, --quiet               Suppress status",
                   "                            lines entirely", ""].join("\n")
        options = completions.section_options(section)
        expect(options).to eq(
          [{short: nil, long: "--dry-run", arg: nil, desc: "Print what would be removed"},
           {short: "-q", long: "--quiet", arg: nil, desc: "Suppress status lines entirely"}]
        )
      end
    end

    it "folds wrapped descriptions into their option and ignores stray lines before the first" do
      section = ["clean options:",
                 "  a stray note",
                 "  --dry-run                 Print what would",
                 "                            be removed", ""].join("\n")
      options = described_class::Completions.section_options(section)
      expect(options.collect { |option| option[:long] }).to eq(["--dry-run"])
      expect(options.first[:desc]).to eq("Print what would be removed")
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
      it "answers `#{command} --help` with that command's usage" do
        expect(run(command, "--help")).to eq(0)
        expect(stdout.string).to include("Usage: simplecov #{command} [options]")
        expect(stderr.string).to be_empty
      end
    end

    it "shows the command's options and not the others'" do
      expect(run("affected", "-h")).to eq(0)
      expect(stdout.string).to include("affected options:").and include("--base REF").and include("--input PATH")
      expect(stdout.string).not_to include("merge options:")
    end

    it "names the command in the header row" do
      expect(run("watch", "--help")).to eq(0)
      expect(stdout.string).to include("Re-run <command> on save")
    end

    it "degrades to a bare usage line for a name with no listing" do
      expect(described_class::Usage.for(described_class, "bogus")).to eq("Usage: simplecov bogus [options]")
    end

    # The whole answer: a usage line, the command's row from the table
    # trimmed of the indentation it is listed under, and the options
    # sections that name it, one blank line apart.
    it "answers with the usage line, the row and the options, spaced apart" do
      expect(described_class::Usage.for(described_class, "clean")).to eq(<<~HELP)
        Usage: simplecov clean [options]

        clean                     Remove the coverage report directory

        clean options:
          --dry-run                 Print what would be removed without deleting
          -q, --quiet               Suppress status lines
      HELP
    end

    # The name is matched literally, so a name that reads as a pattern
    # matches only itself.
    it "reads a command name as a name and not as a pattern" do
      expect(described_class::Usage.for(described_class, "cle.n")).to eq("Usage: simplecov cle.n [options]")
    end

    # A section is one command's options when its heading names that
    # command, and a section with no heading at all names nothing.
    it "takes no section for a command no heading names" do
      expect(described_class::Usage.section_for?("", "clean")).to be(false)
      expect(described_class::Usage.section_for?("Commands:\n  clean\n", "clean")).to be(false)
    end

    # A heading that names the command is still not its options unless
    # it says so.
    it "takes no section from a heading that names the command but lists no options" do
      expect(described_class::Usage.section_for?("clean and friends:\n  --dry-run\n", "clean")).to be(false)
    end

    # A command is a whole word in the heading, not a piece of one, and
    # "options:" is the word that marks the heading rather than a
    # command listed in it.
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

    # The defaults are resolved when the text is asked for, so they
    # describe the run in hand.
    # Every line that names a default, not merely one of them: the text
    # states the same default in more than one place and each has to say
    # what this run would actually use.
    it "names the paths this run would read and write, wherever it names them" do
      lines = described_class::Usage.text(described_class).lines

      # Two of the three name the report; the third names the history
      # file, which has a default of its own.
      inputs = lines.grep(/Read from PATH instead of/).grep_v(/\.history\.json/)
      expect(inputs.size).to eq(2)
      expect(inputs).to all(end_with("instead of #{described_class.default_input}\n"))

      expect(lines.grep(/Write merged resultset/))
        .to all(end_with("(default: #{described_class.default_resultset})\n"))
      expect(lines.grep(/Open PATH instead of/))
        .to all(end_with("instead of #{described_class.default_report}\n"))
      expect(lines.grep(/SimpleCov\.coverage_dir/))
        .to all(include("(#{described_class.coverage_dir} for this run)"))
    end
  end

  describe ".coverage_dir", mutant_expression: ["SimpleCov::CLI#coverage_dir", "SimpleCov::CLI#default_input",
                                                "SimpleCov::CLI#default_report", "SimpleCov::CLI#default_resultset",
                                                "SimpleCov::CLI::Dotfile*"] do
    # Reset memoization between examples so each one sees a fresh
    # discovery from its own cwd.
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
      Dir.mktmpdir do |tmp|
        File.write(File.join(tmp, ".simplecov"), %(SimpleCov.coverage_dir "my/reports"\n))
        Dir.chdir(tmp) do
          expect(described_class.coverage_dir).to eq("my/reports")
        end
      end
    end

    it "falls back to 'coverage' when no .simplecov is found" do
      Dir.mktmpdir do |tmp|
        Dir.chdir(tmp) do
          expect(described_class.coverage_dir).to eq("coverage")
        end
      end
    end

    it "does not start coverage tracking when the dotfile calls SimpleCov.start" do
      Dir.mktmpdir do |tmp|
        File.write(File.join(tmp, ".simplecov"), <<~RUBY)
          SimpleCov.start do
            coverage_dir "from/start_block"
          end
        RUBY
        Dir.chdir(tmp) do
          coverage_was_running = Coverage.running?
          expect(described_class.coverage_dir).to eq("from/start_block")
          # The CLI must not start (or restart) Coverage tracking just
          # by reading the dotfile.
          expect(Coverage.running?).to eq(coverage_was_running)
        end
      end
    end

    it "falls back to 'coverage' and warns when the dotfile raises" do
      Dir.mktmpdir do |tmp|
        File.write(File.join(tmp, ".simplecov"), "raise 'boom'\n")
        Dir.chdir(tmp) do
          expect { expect(described_class.coverage_dir).to eq("coverage") }
            .to output(/simplecov: failed to read coverage_dir.*RuntimeError.*boom/).to_stderr
        end
      end
    end

    it "falls back to 'coverage' and warns when the dotfile has a syntax error" do
      # `load` raises SyntaxError, which is a ScriptError, not a
      # StandardError — a bare rescue would let it crash the CLI.
      Dir.mktmpdir do |tmp|
        File.write(File.join(tmp, ".simplecov"), "SimpleCov.start do\n")
        Dir.chdir(tmp) do
          expect { expect(described_class.coverage_dir).to eq("coverage") }
            .to output(/simplecov: failed to read coverage_dir.*SyntaxError/).to_stderr
        end
      end
    end

    it "restores a host process's configured coverage_dir when the dotfile raises mid-config" do
      configured = SimpleCov.instance_variable_get(:@coverage_dir)
      Dir.mktmpdir do |tmp|
        File.write(File.join(tmp, ".simplecov"), %(SimpleCov.coverage_dir "clobbered"\nraise "boom"\n))
        Dir.chdir(tmp) do
          expect { described_class.coverage_dir }
            .to output(/failed to read coverage_dir/).to_stderr
        end
      end

      expect(SimpleCov.instance_variable_get(:@coverage_dir)).to eq(configured)
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
      it "handles malformed JSON for #{description}" do
        argv = argv_for.call(invalid, valid)

        expect(run(*argv)).to eq(1)
        expect(stdout.string).to be_empty
        expect(stderr.string).to start_with("simplecov #{argv.first}:")
        expect(stderr.string).to include(invalid).and include("isn't valid JSON")
        expect(stderr.string.lines.size).to eq(1)
        expect(stderr.string).not_to include("JSON::ParserError")
      end
    end

    ["null", "[]"].each do |document|
      it "rejects the #{document} top-level JSON value" do
        File.write(invalid, document)

        expect(run("report", "--input", invalid)).to eq(1)
        expect(stderr.string).to include("top-level value must be an object")
      end
    end

    it "rejects invalid UTF-8 before generating JSON output" do
      File.binwrite(invalid, "{\"coverage\":{\"lib/a.rb\":{\"source\":[\"\xFF\"]}}}".b)

      expect(run("coverage", "--input", invalid, "--json", "lib/a.rb")).to eq(1)
      expect(stdout.string).to be_empty
      expect(stderr.string).to include("simplecov coverage:").and include("not valid UTF-8")
      expect(stderr.string.lines.size).to eq(1)
      expect(stderr.string).not_to include("JSON::GeneratorError")
    end

    it "rejects a non-object coverage field" do
      File.write(invalid, JSON.dump("coverage" => []))

      expect(run("uncovered", "--input", invalid)).to eq(1)
      expect(stderr.string).to eq(
        %(simplecov uncovered: input file #{invalid.inspect} isn't valid JSON ("coverage" must be an object)\n)
      )
    end

    it "handles an input path that cannot be read as a file" do
      expect(run("report", "--input", tmp)).to eq(1)
      expect(stderr.string).to include("simplecov report:").and include("cannot read").and include(tmp)
    end

    # Valid JSON with wrong-typed totals used to crash the emitters with
    # NoMethodError/TypeError backtraces instead of a one-line error.
    it "reports wrong-typed \"groups\" as invalid input in both output modes" do
      invalid = File.join(tmp, "bad_groups.json")
      File.write(invalid, JSON.dump("total" => {}, "groups" => [1, 2]))

      expect(run("report", "--input", invalid)).to eq(1)
      expect(stderr.string).to include('"groups" must be an object')

      expect(run("report", "--json", "--input", invalid)).to eq(1)
    end

    it "reports a wrong-typed group entry as invalid input" do
      invalid = File.join(tmp, "bad_group_entry.json")
      File.write(invalid, JSON.dump("total" => {}, "groups" => {"Models" => 5}))

      expect(run("report", "--input", invalid)).to eq(1)
      expect(stderr.string).to include('"groups" must be an object of objects')
    end

    it "reports a wrong-typed \"total\" as invalid input" do
      invalid = File.join(tmp, "bad_total.json")
      File.write(invalid, JSON.dump("total" => []))

      expect(run("report", "--input", invalid)).to eq(1)
      expect(stderr.string).to include('"total" must be an object')
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

    it "names itself in the error when the report cannot be read" do
      absent = File.join(tmp, "absent.json")

      expect(run("coverage", "--input", absent, "lib/a.rb")).to eq(1)
      expect(stderr.string).to eq("simplecov coverage: #{absent} not found\n")
    end

    # The whole message: it names the command, the report it read and
    # the path it could not find, and each of those is read from its own
    # place in the options.
    # Whole message: each of the command, the report and the path is
    # read from its own place, and passing the options themselves would
    # still print something that mentions the report.
    it "names the report and the path when the file is not in it" do
      expect(run("coverage", "--input", json_path, "lib/absent.rb")).to eq(1)
      expect(stderr.string).to eq("simplecov coverage: no entry for lib/absent.rb in #{json_path}\n")
    end

    # Two positional arguments, so the one that is read is identified by
    # position rather than by being the only one there.
    it "reads the path from the first positional argument" do
      expect(run("coverage", "--input", json_path, abs_filename, "lib/other.rb")).to eq(0)
      expect(stdout.string).to include(abs_filename)
    end

    it "names the report and the path when the entry is not an object" do
      File.write(json_path, JSON.dump("coverage" => {"lib/a.rb" => "junk"}))

      expect(run("coverage", "--input", json_path, "lib/a.rb")).to eq(1)
      expect(stderr.string).to eq(
        "simplecov coverage: input file #{json_path.inspect} isn't valid JSON " \
        "(entry for lib/a.rb must be an object)\n"
      )
    end

    # A percent without its counts beside it still has a row to print,
    # and the counts it does not have read as zero.
    it "prints a criterion whose counts are missing" do
      File.write(json_path, JSON.dump("coverage" => {"lib/a.rb" => {"lines_covered_percent" => 66.67}}))

      expect(run("coverage", "--input", json_path, "lib/a.rb")).to eq(0)
      expect(stdout.string).to include("(0 / 0)")
    end

    it "omits a criterion the report never measured" do
      File.write(json_path, JSON.dump("coverage" => {"lib/a.rb" => {
                                        "lines_covered_percent" => 66.67,
                                        "covered_lines" => 2, "total_lines" => 3
                                      }}))

      expect(run("coverage", "--input", json_path, "lib/a.rb")).to eq(0)
      expect(stdout.string).to include("Line:")
      expect(stdout.string).not_to include("Branch:")
    end

    it "reads a percent that arrived as a string" do
      File.write(json_path, JSON.dump("coverage" => {"lib/a.rb" => {
                                        "lines_covered_percent" => "66.67",
                                        "covered_lines" => 2, "total_lines" => 3
                                      }}))

      expect(run("coverage", "--input", json_path, "lib/a.rb")).to eq(0)
      expect(stdout.string).to include("66.67%")
    end

    it "prints stats for a matching path (absolute)" do
      expect(run("coverage", "--input", json_path, abs_filename)).to eq(0)
      out = stdout.string
      expect(out).to include(abs_filename)
      expect(out).to match(%r{Line:\s+66\.67%\s+\(2 / 3\)})
      expect(out).to match(%r{Branch:\s+50\.00%\s+\(1 / 2\)})
    end

    it "names the candidates for an ambiguous subpath" do
      payload = {"coverage" => {
        "/abs/project/app/models/user.rb" => {"lines" => [1]},
        "/abs/project/lib/models/user.rb" => {"lines" => [1]}
      }}
      File.write(json_path, JSON.dump(payload))

      expect(run("coverage", "--input", json_path, "models/user.rb")).to eq(1)
      expect(stderr.string).to include("matches 2 files")
        .and include("/abs/project/app/models/user.rb")
        .and include("/abs/project/lib/models/user.rb")
    end

    it "matches a project-relative path via end_with on the absolute key" do
      expect(run("coverage", "--input", json_path, "app/models/user.rb")).to eq(0)
      expect(stdout.string).to include(abs_filename)
    end

    it "errors when the input file is missing" do
      expect(run("coverage", "--input", "/no/such/coverage.json", "x.rb")).to eq(1)
      expect(stderr.string).to include("not found")
    end

    it "errors when the requested file isn't in the report" do
      expect(run("coverage", "--input", json_path, "lib/missing.rb")).to eq(1)
      expect(stderr.string).to include("no entry for lib/missing.rb")
    end

    # A wrong-typed per-file entry used to crash print_human with
    # NoMethodError instead of the one-line error the siblings print.
    it "errors when the matched entry is not an object" do
      File.write(json_path, JSON.dump("coverage" => {abs_filename => "junk"}))

      expect(run("coverage", "--input", json_path, abs_filename)).to eq(1)
      expect(stderr.string).to include("entry for #{abs_filename} must be an object")
    end

    it "errors when the file argument is missing" do
      expect(run("coverage", "--input", json_path)).to eq(1)
      expect(stderr.string).to include("missing file argument")
    end

    it "emits the raw JSON entry under --json" do
      expect(run("coverage", "--input", json_path, "--json", abs_filename)).to eq(0)
      parsed = JSON.parse(stdout.string)
      expect(parsed.keys).to eq([abs_filename])
      expect(parsed[abs_filename]["lines_covered_percent"]).to eq(66.67)
    end

    context "with colorization" do
      it "colorizes percentages when Color.enabled? is true" do
        allow(SimpleCov::Color).to receive(:enabled?).and_return(true)
        expect(run("coverage", "--input", json_path, abs_filename)).to eq(0)
        # 66.67% is below the yellow threshold, so red (\e[31m)
        expect(stdout.string).to match(/\e\[31m66\.67%\e\[0m/)
      end

      it_behaves_like "a --no-color subcommand" do
        let(:no_color_argv) { ["coverage", "--input", json_path, "--no-color", abs_filename] }
      end
    end
  end

  describe "run subcommand", mutant_expression: "SimpleCov::CLI::Run*" do
    # A mutation respelling `Kernel.exec` as a bare exec would replace
    # the example process with the command under test, which exits
    # cleanly and reports nothing — read by mutation analysis as a
    # pass. Arm every example in this pool so that spelling fails an
    # example instead of ending the process.
    before do
      allow(described_class::Run).to receive(:exec) { raise "exec reached the module, not Kernel" }
    end

    it "errors and exits 1 when no command is given" do
      expect(run("run")).to eq(1)
      expect(stderr.string).to include("missing command")
    end

    it "execs through Kernel by name, never through a bare exec on itself" do
      allow(Kernel).to receive(:exec)
      allow(described_class::Run).to receive(:exec) # quiet the armed raise; the point is who was asked

      described_class::Run.send(:exec_command, {"MARK" => "1"}, ["true", "--flag"])

      expect(Kernel).to have_received(:exec).with({"MARK" => "1"}, "true", "--flag")
      expect(described_class::Run).not_to have_received(:exec)
    end

    it "execs the command with RUBYOPT set to load the autostart shim" do
      # Real Kernel.exec never returns; the stub does, but the side
      # effect (env + argv) is what we're verifying.
      captured_env = nil
      captured_argv = nil
      allow(Kernel).to receive(:exec) do |env, *cmd|
        captured_env = env
        captured_argv = cmd
      end

      run("run", "echo", "hello")
      expect(captured_argv).to eq(%w[echo hello])
      expect(captured_env["RUBYOPT"]).to include("-r#{described_class::Run::AUTOSTART}")
    end

    # The child needs the environment it was launched in, not just the
    # one variable this command sets. Probed with a variable of the
    # example's own: a system one like PATH is spelled with whatever
    # casing the platform fancies.
    it "passes the whole environment through, not only RUBYOPT" do
      captured_env = nil
      allow(Kernel).to receive(:exec) { |env, *_cmd| captured_env = env }

      with_env("SIMPLECOV_SPEC_CARRIED" => "through") do
        run("run", "true")
      end
      expect(captured_env).to include("SIMPLECOV_SPEC_CARRIED" => "through")
    end

    # A RUBYOPT padded with spaces is a RUBYOPT of its own, and joining
    # to it without trimming leaves a doubled separator.
    it "trims an existing RUBYOPT before joining to it" do
      previous = ENV.fetch("RUBYOPT", nil)
      ENV["RUBYOPT"] = "  -W0  "

      captured_env = nil
      allow(Kernel).to receive(:exec) { |env, *_cmd| captured_env = env }
      run("run", "true")
      expect(captured_env["RUBYOPT"]).to eq("-W0 -r#{described_class::Run::AUTOSTART}")
    ensure
      ENV["RUBYOPT"] = previous
    end

    it "reports a command that is not there, and answers the shell's own code for it" do
      allow(Kernel).to receive(:exec).and_raise(Errno::ENOENT, "nope")

      expect(run("run", "nope")).to eq(127)
      expect(stderr.string).to eq("simplecov run: No such file or directory - nope\n")
    end

    it "errors and exits 1 when no command is given, saying so" do
      expect(run("run")).to eq(1)
      expect(stderr.string).to eq("simplecov run: missing command\n")
    end

    it "preserves an existing RUBYOPT alongside the injection" do
      previous = ENV.fetch("RUBYOPT", nil)
      ENV["RUBYOPT"] = "-W0"

      captured_env = nil
      allow(Kernel).to receive(:exec) { |env, *_cmd| captured_env = env }
      run("run", "true")
      expect(captured_env["RUBYOPT"]).to start_with("-W0 -r")
    ensure
      ENV["RUBYOPT"] = previous
    end

    it "sets RUBYOPT to just the injection when none was already set" do
      previous = ENV.fetch("RUBYOPT", nil)
      ENV.delete("RUBYOPT")

      captured_env = nil
      allow(Kernel).to receive(:exec) { |env, *_cmd| captured_env = env }
      run("run", "true")
      expect(captured_env["RUBYOPT"]).to eq("-r#{described_class::Run::AUTOSTART}")
    ensure
      ENV["RUBYOPT"] = previous
    end

    it "drops a leading -- separator before the command" do
      captured_argv = nil
      allow(Kernel).to receive(:exec) { |_env, *cmd| captured_argv = cmd }
      run("run", "--", "echo", "hello")
      expect(captured_argv).to eq(%w[echo hello])
    end

    it "returns 127 with a friendly message when the command can't be found" do
      allow(Kernel).to receive(:exec).and_raise(Errno::ENOENT, "no such command nope")
      expect(run("run", "nope")).to eq(127)
      expect(stderr.string).to include("no such command nope")
    end

    # End-to-end: actually invoke a child Ruby process and check that
    # the autostart shim fires (Coverage.running? becomes true).
    it "actually starts SimpleCov in a child process" do
      script = <<~RUBY
        require "coverage"
        puts Coverage.running?
      RUBY
      cmd = ["ruby", "-I", File.expand_path("../lib", __dir__), "-e", script]
      output = nil
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          autostart = described_class::Run::AUTOSTART
          # capture3 (not capture2) so the autostart shim's
          # "framework not recognized" warning from the child's stderr
          # doesn't leak into the test runner's output.
          output, _err, _status = Open3.capture3({"RUBYOPT" => "-r#{autostart}"}, *cmd)
        end
      end
      expect(output.lines.first.strip).to eq("true")
    end
  end

  describe "report subcommand", mutant_expression: ["SimpleCov::CLI::Report*", "SimpleCov::CLI::CommandHelpers*"] do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-report-spec-") }
    let(:json_path) { File.join(tmp, "coverage.json") }

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

    # The whole block, not fragments of it: the totals row, then each
    # group in the order the report carries them, each criterion aligned
    # in its own column, and a blank line between blocks. A criterion
    # with nothing relevant is left out rather than printed as 0/0.
    it "prints the totals and every group, whole" do
      expect(run("report", "--input", json_path, "--no-color")).to eq(0)
      expect(stdout.string).to eq(<<~TEXT)
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

    it "prints the All Files totals" do
      expect(run("report", "--input", json_path)).to eq(0)
      expect(stdout.string).to include("All Files")
      expect(stdout.string).to match(%r{Line:\s+80\.00%\s+\(80 / 100\)})
      expect(stdout.string).to match(%r{Branch:\s+90\.00%\s+\(9 / 10\)})
    end

    # Valid JSON is not enough: a wrong-typed section used to reach the
    # emitters and crash with a backtrace instead of a one-line error.
    it "refuses a totals section that is not an object" do
      File.write(json_path, JSON.dump("total" => "junk"))

      expect(run("report", "--input", json_path)).to eq(1)
      expect(stderr.string)
        .to eq(%(simplecov report: input file #{json_path.inspect} isn't valid JSON ("total" must be an object)\n))
    end

    it "refuses a groups section that is not an object of objects" do
      ["junk", {"Models" => "junk"}].each do |groups|
        File.write(json_path, JSON.dump("total" => {}, "groups" => groups))
        stderr.truncate(0) && stderr.rewind

        expect(run("report", "--input", json_path)).to eq(1), "for #{groups.inspect}"
        prefix = %(simplecov report: input file #{json_path.inspect} isn't valid JSON)
        expect(stderr.string).to eq(%(#{prefix} ("groups" must be an object of objects)\n))
      end
    end

    it "prints nothing but a blank line for a report carrying no sections" do
      File.write(json_path, JSON.dump({}))

      expect(run("report", "--input", json_path)).to eq(0)
      expect(stdout.string).to eq("All Files\n\n")
    end

    it "skips a criterion with zero relevant entries" do
      expect(run("report", "--input", json_path)).to eq(0)
      expect(stdout.string).not_to include("Method:")
    end

    # Sections the report never carried, and sections carrying half of
    # what they should: the row is either printed from what is there or
    # left out, never a crash.
    it "prints what a half-filled section carries and skips one with no total" do
      File.write(json_path, JSON.dump(
                              "total" => {
                                "lines" => {"covered" => 8, "total" => 10},
                                "branches" => {"percent" => 50.0, "covered" => 1},
                                "methods" => {"percent" => 50.0, "total" => 4}
                              }
                            ))

      expect(run("report", "--input", json_path, "--no-color")).to eq(0)
      expect(stdout.string).to eq("All Files\n  Line:   0.00% (8 / 10)\n  Method: 50.00% (0 / 4)\n\n")
    end

    it "prints a report with no total and no groups at all" do
      File.write(json_path, JSON.dump("coverage" => {}))

      expect(run("report", "--input", json_path)).to eq(0)
      expect(stdout.string).to eq("All Files\n\n")
    end

    it "emits an empty payload for a report with no total and no groups at all" do
      File.write(json_path, JSON.dump("coverage" => {}))

      expect(run("report", "--input", json_path, "--json")).to eq(0)
      expect(JSON.parse(stdout.string)).to eq("total" => {}, "groups" => {})
    end

    it "carries a half-filled section into the payload as it stands" do
      File.write(json_path, JSON.dump(
                              "total" => {
                                "lines" => {"covered" => 8, "total" => 10},
                                "branches" => {"percent" => 50.0, "covered" => 1},
                                "methods" => {"percent" => 50.0, "total" => 4}
                              },
                              "groups" => {"Models" => {"lines" => {"total" => 0}, "branches" => [1, 2]}}
                            ))

      expect(run("report", "--input", json_path, "--json")).to eq(0)
      expect(JSON.parse(stdout.string)).to eq(
        "total" => {
          "lines" => {"percent" => nil, "covered" => 8, "total" => 10},
          "methods" => {"percent" => 50.0, "covered" => nil, "total" => 4}
        },
        "groups" => {"Models" => {}}
      )
    end

    # A section carrying something other than an object is as much a
    # non-section as one carrying nothing.
    it "skips a criterion whose section is not an object" do
      File.write(json_path, JSON.dump("total" => {"lines" => [1, 2]}))

      expect(run("report", "--input", json_path, "--no-color")).to eq(0)
      expect(stdout.string).to eq("All Files\n\n")
    end

    it "prints a percentage as reported, to the digit" do
      File.write(json_path, JSON.dump("total" => {"lines" => {"percent" => 66.67, "covered" => 2, "total" => 3}}))

      expect(run("report", "--input", json_path, "--no-color")).to eq(0)
      expect(stdout.string).to eq("All Files\n  Line:   66.67% (2 / 3)\n\n")
    end

    it "prints group totals after the All Files row" do
      expect(run("report", "--input", json_path)).to eq(0)
      expect(stdout.string).to include("Models")
      expect(stdout.string.index("All Files")).to be < stdout.string.index("Models")
    end

    it "labels a user group named All Files distinctly" do
      expect(run("report", "--input", json_path)).to eq(0)
      expect(stdout.string).to include("All Files\n")
      expect(stdout.string).to include("All Files (group)\n")
    end

    it "errors when the input file is missing, naming the subcommand" do
      expect(run("report", "--input", "/no/such.json")).to eq(1)
      expect(stderr.string).to eq("simplecov report: /no/such.json not found\n")
    end

    it "emits namespaced totals and groups as JSON under --json" do
      expect(run("report", "--input", json_path, "--json")).to eq(0)
      payload = JSON.parse(stdout.string)
      expect(payload["total"]).to include("lines" => {"percent" => 80.0, "covered" => 80, "total" => 100})
      expect(payload["total"]).to include("branches" => {"percent" => 90.0, "covered" => 9, "total" => 10})
      expect(payload["total"]).not_to include("methods")
      expect(payload.dig("groups", "Models"))
        .to include("lines" => {"percent" => 80.0, "covered" => 40, "total" => 50})
      expect(payload.dig("groups", "All Files"))
        .to include("lines" => {"percent" => 50.0, "covered" => 1, "total" => 2})
    end

    context "with colorization" do
      it "colorizes percentages by threshold when Color.enabled? is true" do
        allow(SimpleCov::Color).to receive(:enabled?).and_return(true)
        expect(run("report", "--input", json_path)).to eq(0)
        # 80% is yellow, 90% is green
        expect(stdout.string).to match(/\e\[33m80\.00%\e\[0m/)
        expect(stdout.string).to match(/\e\[32m90\.00%\e\[0m/)
      end

      it "colorizes a group's percentages too, not just the totals row" do
        allow(SimpleCov::Color).to receive(:enabled?).and_return(true)

        expect(run("report", "--input", json_path)).to eq(0)
        models = stdout.string.split("Models\n").last
        expect(models).to match(/\e\[33m80\.00%\e\[0m/)
      end

      it_behaves_like "a --no-color subcommand" do
        let(:no_color_argv) { ["report", "--input", json_path, "--no-color"] }
      end
    end
  end

  describe "tests subcommand", mutant_expression: ["SimpleCov::CLI::Tests*", "SimpleCov::CLI::CommandHelpers*"] do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-tests-spec-") }
    let(:json_path) { File.join(tmp, "coverage.json") }
    let(:result_file) { "/abs/project/lib/result.rb" }
    let(:quiet_file) { "/abs/project/lib/quiet.rb" }

    # Two contexts: index 0 covers lines 2 and 3 of result.rb, index 1
    # covers line 3 only. quiet.rb was covered by no recorded context.
    let(:payload) do
      {
        "contexts" => ["spec/result_spec.rb:42", "spec/result_spec.rb:57"],
        "coverage" => {
          result_file => {"lines" => [nil, 1, 2, 0], "contexts" => {"0" => "6", "1" => "4"}},
          quiet_file => {"lines" => [1, nil]}
        }
      }
    end

    before { File.write(json_path, JSON.dump(payload)) }

    after { FileUtils.remove_entry(tmp) }

    it "lists every recorded test, sorted, with a bare invocation" do
      expect(run("tests", "--input", json_path)).to eq(0)
      expect(stdout.string).to eq("spec/result_spec.rb:42\nspec/result_spec.rb:57\n")
    end

    it "narrows to the tests touching a file" do
      expect(run("tests", "--input", json_path, "lib/result.rb")).to eq(0)
      expect(stdout.string).to eq("spec/result_spec.rb:42\nspec/result_spec.rb:57\n")
    end

    it "narrows to the tests covering one line" do
      expect(run("tests", "--input", json_path, "lib/result.rb:2")).to eq(0)
      expect(stdout.string).to eq("spec/result_spec.rb:42\n")
    end

    it "answers an empty list, with a stderr note, for a line no test covers" do
      expect(run("tests", "--input", json_path, "lib/result.rb:4")).to eq(0)
      expect(stdout.string).to be_empty
      expect(stderr.string).to eq("simplecov tests: no recorded test covers lib/result.rb:4\n")
    end

    it "answers an empty list for a covered file no recorded context touched" do
      expect(run("tests", "--input", json_path, "lib/quiet.rb")).to eq(0)
      expect(stdout.string).to be_empty
      expect(stderr.string).to eq("simplecov tests: no recorded test covers lib/quiet.rb\n")
    end

    it "emits JSON arrays under --json, empty results included" do
      expect(run("tests", "--input", json_path, "--json", "lib/result.rb:3")).to eq(0)
      expect(JSON.parse(stdout.string)).to eq(["spec/result_spec.rb:42", "spec/result_spec.rb:57"])

      stdout.truncate(0) && stdout.rewind
      expect(run("tests", "--input", json_path, "--json", "lib/result.rb:4")).to eq(0)
      expect(JSON.parse(stdout.string)).to eq([])
      expect(stderr.string).to be_empty
    end

    it "notes an empty recording on stderr for a bare invocation" do
      File.write(json_path, JSON.dump(payload.merge("contexts" => [])))
      expect(run("tests", "--input", json_path)).to eq(0)
      expect(stdout.string).to be_empty
      expect(stderr.string).to eq("simplecov tests: no tests recorded\n")
    end

    it "explains what to enable when the document carries no contexts" do
      File.write(json_path, JSON.dump({"coverage" => {}}))
      expect(run("tests", "--input", json_path)).to eq(1)
      expect(stderr.string).to eq(
        "simplecov tests: no test contexts recorded in #{json_path}. Enable `track_tests` in " \
        "your `SimpleCov.start` block and rerun the suite to record them\n"
      )
    end

    # A found-but-wrong-typed entry is malformed input, not a missing
    # file — the same distinction the coverage subcommand draws.
    it "reports a wrong-typed entry as invalid input, not as missing" do
      File.write(json_path, JSON.dump(payload.merge("coverage" => {result_file => "junk"})))
      expect(run("tests", "--input", json_path, "lib/result.rb")).to eq(1)
      expect(stderr.string).to eq(
        "simplecov tests: input file #{json_path.inspect} isn't valid JSON " \
        "(entry for lib/result.rb must be an object)\n"
      )
    end

    it "documents its --json in the usage text" do
      expect(run("help")).to eq(0)
      expect(stdout.string).to include("tests options:")
    end

    it "reports an unknown file like the coverage subcommand does" do
      expect(run("tests", "--input", json_path, "lib/nope.rb")).to eq(1)
      expect(stderr.string).to eq("simplecov tests: no entry for lib/nope.rb in #{json_path}\n")
    end

    it "names the candidates for an ambiguous subpath" do
      payload["coverage"][result_file.sub("/lib/", "/app/")] = {"lines" => [1]}
      File.write(json_path, JSON.dump(payload))

      expect(run("tests", "--input", json_path, "result.rb")).to eq(1)
      expect(stderr.string).to eq(
        "simplecov tests: result.rb matches 2 files in #{json_path}: " \
        "/abs/project/app/result.rb, /abs/project/lib/result.rb (use a longer path to pick one)\n"
      )
    end

    it "rejects a non-positive line number as a parse error" do
      expect(run("tests", "--input", json_path, "lib/result.rb:0")).to eq(1)
      expect(stderr.string).to eq("simplecov tests: line number must be positive\n")
    end

    it "reports a missing input file under its own command name" do
      missing = File.join(tmp, "nope.json")
      expect(run("tests", "--input", missing)).to eq(1)
      expect(stderr.string).to eq("simplecov tests: #{missing} not found\n")
    end

    it "treats a malformed per-file contexts table as invalid input" do
      [{"9" => "6"}, {"x" => "6"}, {"0" => "zz"}, "junk"].each do |malformed|
        payload["coverage"][result_file]["contexts"] = malformed
        File.write(json_path, JSON.dump(payload))
        stderr.truncate(0) && stderr.rewind
        expect(run("tests", "--input", json_path, "lib/result.rb")).to eq(1), "expected 1 for #{malformed.inspect}"
        expect(stderr.string).to eq(
          "simplecov tests: input file #{json_path.inspect} isn't valid JSON " \
          "(entry for lib/result.rb carries a malformed \"contexts\" table)\n"
        )
      end
    end

    it "treats a non-object coverage section as invalid input for a file query" do
      File.write(json_path, JSON.dump(payload.merge("coverage" => "junk")))
      expect(run("tests", "--input", json_path, "lib/result.rb")).to eq(1)
      expect(stderr.string).to eq(
        %(simplecov tests: input file #{json_path.inspect} isn't valid JSON ("coverage" must be an object)\n)
      )
    end

    it "treats an absent coverage section as invalid input for a file query" do
      File.write(json_path, JSON.dump({"contexts" => payload["contexts"]}))
      expect(run("tests", "--input", json_path, "lib/result.rb")).to eq(1)
      expect(stderr.string).to eq(
        %(simplecov tests: input file #{json_path.inspect} isn't valid JSON ("coverage" must be an object)\n)
      )
    end

    it "treats a malformed document-level contexts list as invalid input" do
      File.write(json_path, JSON.dump(payload.merge("contexts" => "junk")))
      expect(run("tests", "--input", json_path)).to eq(1)
      expect(stderr.string).to eq(
        %(simplecov tests: input file #{json_path.inspect} isn't valid JSON ("contexts" must be an array of strings)\n)
      )
    end

    # Unit examples over the query helpers, pinning behavior the composed
    # CLI examples can't tell apart operator by operator.
    describe "query helpers" do
      let(:tests) { SimpleCov::CLI::Tests }

      it "splits a target into path and line the way the docs promise" do
        expect(tests.split_target(nil)).to eq(path: nil, line: nil)
        expect(tests.split_target("a.rb")).to eq(path: "a.rb", line: nil)
        expect(tests.split_target("a.rb:42")).to eq(path: "a.rb", line: 42)
        expect(tests.split_target("a.rb:4x")).to eq(path: "a.rb:4x", line: nil)
        expect(tests.split_target("C:/x.rb")).to eq(path: "C:/x.rb", line: nil)
        expect(tests.split_target("a.rb:42:7")).to eq(path: "a.rb:42", line: 7)
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

      it "selects ids by line bit, sorted, and all ids without a line" do
        expect(tests.ids_from({0 => 0b10, 1 => 0b01}, %w[b a], 2)).to eq(["b"])
        expect(tests.ids_from({1 => 0b1, 0 => 0b1}, %w[a z], nil)).to eq(%w[a z])
      end

      it "keeps the first positional argument as the target" do
        opts = tests.parse(["a.rb:1", "z.rb:2"])
        expect(opts[:target]).to eq("a.rb:1")
        expect(opts[:path]).to eq("a.rb")
        expect(opts[:line]).to eq(1)
      end

      it "reads an all-digit target as a path, not a line" do
        expect(tests.split_target("42")).to eq(path: "42", line: nil)
      end

      it "reads a zero-padded line number in base ten" do
        expect(tests.split_target("a.rb:08")).to eq(path: "a.rb", line: 8)
      end

      it "keeps ids the answer's only stdout even for an empty answer" do
        out = StringIO.new
        expect(tests.emit([], {json: false, target: nil, redundant: nil}, out, StringIO.new)).to be_nil
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

      it "stops at the first reported defect even under --redundant" do
        io = StringIO.new
        document = {"contexts" => ["t"], "coverage" => "junk"}
        expect(tests.resolve(document, {path: "p", redundant: true, input: "i"}, io)).to be_nil
        expect(io.string.lines.count).to eq(1)
      end

      it "locates the very entry through Hash-subclass document sections" do
        subclass = Class.new(Hash)
        entry = subclass.new.merge!("contexts" => {"0" => "1"})
        coverage = subclass.new.merge!("/abs/x.rb" => entry)
        opts = {path: "/abs/x.rb", input: "x"}
        expect(tests.locate_entry({"coverage" => coverage}, opts, StringIO.new)).to equal(entry)
      end

      it "reads an absent or Hash-subclass contexts key for the file's table" do
        expect(tests.context_table({}, [], {}, StringIO.new)).to eq({})
        raw = Class.new(Hash).new.merge!("0" => "6")
        expect(tests.context_table({"contexts" => raw}, ["a"], {}, StringIO.new)).to eq(0 => 6)
      end
    end

    describe "--redundant" do
      let(:other_file) { "/abs/project/lib/other.rb" }

      # Four contexts: :10 uniquely covers line 2 of result.rb and shares
      # line 3, :20 covers only that shared line, :30 uniquely covers
      # other.rb, and :40 ran without covering anything. The recording
      # order deliberately differs from the sorted order, so an unsorted
      # answer is distinguishable.
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

      it "lists the tests whose covered lines other tests also cover" do
        expect(run("tests", "--input", json_path, "--redundant")).to eq(0)
        expect(stdout.string).to eq("spec/b_spec.rb:20\nspec/d_spec.rb:40\n")
      end

      it "narrows to the redundant tests touching a file" do
        expect(run("tests", "--input", json_path, "--redundant", "lib/result.rb")).to eq(0)
        expect(stdout.string).to eq("spec/b_spec.rb:20\n")
      end

      it "answers an empty list, with a stderr note, for a line only unique tests cover" do
        expect(run("tests", "--input", json_path, "--redundant", "lib/result.rb:2")).to eq(0)
        expect(stdout.string).to be_empty
        expect(stderr.string).to eq("simplecov tests: no redundant test covers lib/result.rb:2\n")
      end

      # Mutual subsumption is the honest answer, not a bug: each of the
      # two could go, but not both, so the list is per-test rather than
      # a deletable set.
      it "lists both of two tests covering exactly the same lines" do
        payload["coverage"][result_file]["contexts"] = {"1" => "6", "2" => "6"}
        File.write(json_path, JSON.dump(payload))
        expect(run("tests", "--input", json_path, "--redundant")).to eq(0)
        expect(stdout.string).to eq("spec/a_spec.rb:10\nspec/b_spec.rb:20\nspec/d_spec.rb:40\n")
      end

      it "notes on stderr when every recorded test covers something uniquely" do
        File.write(json_path, JSON.dump(
                                "contexts" => ["spec/a_spec.rb:10", "spec/c_spec.rb:30"],
                                "coverage" => {result_file => {"lines" => [1, 1],
                                                               "contexts" => {"0" => "1", "1" => "2"}}}
                              ))
        expect(run("tests", "--input", json_path, "--redundant")).to eq(0)
        expect(stdout.string).to be_empty
        expect(stderr.string)
          .to eq("simplecov tests: no redundant tests, every recorded test covers at least one line uniquely\n")
      end

      it "keeps the no-recording note when the contexts list is empty" do
        File.write(json_path, JSON.dump("contexts" => [], "coverage" => {quiet_file => {"lines" => [1, nil]}}))
        expect(run("tests", "--input", json_path, "--redundant")).to eq(0)
        expect(stdout.string).to be_empty
        expect(stderr.string).to eq("simplecov tests: no tests recorded\n")
      end

      it "emits the redundant ids as a JSON array under --json" do
        expect(run("tests", "--input", json_path, "--redundant", "--json")).to eq(0)
        expect(JSON.parse(stdout.string)).to eq(["spec/b_spec.rb:20", "spec/d_spec.rb:40"])
      end

      # The sweep reads every file's table, so a malformed table poisons
      # the whole answer even when no query names its file — the same
      # all-or-nothing tolerance the targeted queries apply. The stderr
      # assertions are exact: the complaint must name the right file and
      # the right defect, under the command's own name, with nothing else.
      it "treats a malformed contexts table anywhere in the sweep as invalid input" do
        [{"9" => "1"}, "junk"].each do |malformed|
          payload["coverage"][other_file]["contexts"] = malformed
          File.write(json_path, JSON.dump(payload))
          stderr.truncate(0) && stderr.rewind
          expect(run("tests", "--input", json_path, "--redundant")).to eq(1), "expected 1 for #{malformed.inspect}"
          expect(stderr.string).to eq(
            %(simplecov tests: input file #{json_path.inspect} isn't valid JSON ) +
            %[(entry for #{other_file} carries a malformed "contexts" table)\n]
          )
        end
      end

      it "treats a non-object coverage section as invalid input for the bare sweep" do
        File.write(json_path, JSON.dump(payload.merge("coverage" => "junk")))
        expect(run("tests", "--input", json_path, "--redundant")).to eq(1)
        expect(stderr.string).to eq(
          %(simplecov tests: input file #{json_path.inspect} isn't valid JSON ("coverage" must be an object)\n)
        )
      end

      it "treats an absent coverage section like any other non-object one" do
        File.write(json_path, JSON.dump({"contexts" => payload["contexts"]}))
        expect(run("tests", "--input", json_path, "--redundant")).to eq(1)
        expect(stderr.string).to eq(
          %(simplecov tests: input file #{json_path.inspect} isn't valid JSON ("coverage" must be an object)\n)
        )
      end

      it "treats a wrong-typed entry anywhere in the sweep as invalid input" do
        payload["coverage"][quiet_file] = "junk"
        File.write(json_path, JSON.dump(payload))
        expect(run("tests", "--input", json_path, "--redundant")).to eq(1)
        expect(stderr.string).to eq(
          %(simplecov tests: input file #{json_path.inspect} isn't valid JSON ) +
          %((entry for #{quiet_file} must be an object)\n)
        )
      end

      # Unit examples over the pure helpers: the composed CLI examples
      # can't distinguish every operator, so these pin the arithmetic
      # (and the sweep's tolerance for a Hash subclass) directly.
      describe "sweep helpers" do
        let(:redundancy) { SimpleCov::CLI::Tests::Redundancy }

        it "extracts the bits set in exactly one bitmap" do
          expect(redundancy.lone_bits({})).to eq(0)
          expect(redundancy.lone_bits({0 => 0b1})).to eq(0b1)
          expect(redundancy.lone_bits({0 => 0b0110, 1 => 0b0100, 2 => 0b1100})).to eq(0b1010)
          expect(redundancy.lone_bits({0 => 0b1, 1 => 0b1, 2 => 0b1})).to eq(0)
        end

        it "credits each uniquely covered bit to its owning context" do
          expect(redundancy.unique_owners([{0 => 0b11, 1 => 0b10}], 3)).to eq([true, false, false])
          expect(redundancy.unique_owners([{0 => 0b1}, {1 => 0b10}], 2)).to eq([true, true])
        end

        it "decodes a table arriving as a Hash subclass" do
          raw = Class.new(Hash).new
          raw["0"] = "6"
          expect(redundancy.swept_table({"contexts" => raw}, ["spec/a_spec.rb:1"])).to eq(0 => 6)
        end

        it "complains about the table, not the entry, for a Hash-subclass entry" do
          entry = Class.new(Hash).new
          expect(redundancy.complaint("/p.rb", entry)).to eq(%(entry for /p.rb carries a malformed "contexts" table))
          expect(redundancy.complaint("/p.rb", "junk")).to eq("entry for /p.rb must be an object")
        end

        it "renders a nil input path rather than raising" do
          io = StringIO.new
          expect(redundancy.invalid({input: nil}, io, "why")).to be_nil
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
        expect(run("help")).to eq(0)
        expect(stdout.string).to include("--redundant")
      end
    end
  end

  describe "show subcommand", mutant_expression: "SimpleCov::CLI::Show*" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-show-spec-") }
    let(:json_path) { File.join(tmp, "coverage.json") }
    let(:code_path) { File.join(tmp, "lib/code.rb") }

    let(:source) do
      ["def call(baseline)", "  rows = compare", "  return 1 if rows.empty?", "",
       "# comment", "again", "done", "more", "covered", "last"]
    end
    let(:entry) do
      {
        "source" => source,
        "lines" => [1, 1, 0, nil, nil, 0, 0, 0, 1, 0],
        "branches" => [{"report_line" => 2, "coverage" => 0}, {"report_line" => 1, "coverage" => 3}, "junk"],
        "methods" => [{"start_line" => 1, "coverage" => 0}, {"start_line" => "x", "coverage" => 0}, "junk"]
      }
    end
    let(:payload) { {"coverage" => {code_path => entry}} }

    before { File.write(json_path, JSON.dump(payload)) }

    after { FileUtils.rm_rf(tmp) }

    it "prints the source with hit counts and miss markers" do
      expect(run("show", "--input", json_path, "lib/code.rb")).to eq(0)
      expect(stdout.string).to eq(<<~OUT)
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

    it "joins a line's markers when it misses more than one way" do
      entry["branches"][0]["report_line"] = 3
      File.write(json_path, JSON.dump(payload))
      expect(run("show", "--input", json_path, "lib/code.rb")).to eq(0)
      expect(stdout.string).to include("^ missed, branch missed")
    end

    it "collapses the misses to greppable ranges under --uncovered-only" do
      expect(run("show", "--input", json_path, "--uncovered-only", "lib/code.rb")).to eq(0)
      expect(stdout.string).to eq("lib/code.rb:3,6-8,10\n")
    end

    it "sweeps the whole project under a bare --uncovered-only" do
      payload["coverage"][File.join(SimpleCov.root, "lib/zzz.rb")] = {"lines" => [0]}
      payload["coverage"][File.join(SimpleCov.root, "lib/rooted.rb")] = {"lines" => [1, 0, 0, nil, 0]}
      payload["coverage"][File.join(tmp, "lib/covered.rb")] = {"lines" => [1, 1]}
      payload["coverage"][File.join(tmp, "lib/junk.rb")] = "junk"
      File.write(json_path, JSON.dump(payload))

      # Sorted by the path shown, not by the order the report happens
      # to list them in.
      expect(run("show", "--input", json_path, "--uncovered-only")).to eq(0)
      expect(stdout.string).to eq(<<~OUT)
        #{code_path}:3,6-8,10
        lib/rooted.rb:2-3,5
        lib/zzz.rb:1
      OUT
    end

    it "reports a missing input on a bare sweep like everywhere else" do
      missing = File.join(tmp, "nope.json")
      expect(run("show", "--input", missing, "--uncovered-only")).to eq(1)
      expect(stderr.string).to eq("simplecov show: #{missing} not found\n")
    end

    it "names the subcommand and the input when the file itself is missing" do
      missing = File.join(tmp, "nope.json")
      expect(run("show", "--input", missing, "lib/code.rb")).to eq(1)
      expect(stderr.string).to eq("simplecov show: #{missing} not found\n")
    end

    # A line-coverage-only entry is a Hash whose "lines" is a list. A
    # Hash whose "lines" is anything else has no gutter to sweep, and
    # an entry that is no Hash has nothing to ask at all.
    it "passes over an entry whose lines are no lines at all in a sweep" do
      payload["coverage"][File.join(tmp, "lib/odd.rb")] = {"lines" => "junk"}
      payload["coverage"][File.join(tmp, "lib/list.rb")] = [1, 0]
      payload["coverage"][File.join(tmp, "lib/none.rb")] = {"branches" => []}
      File.write(json_path, JSON.dump(payload))

      expect(run("show", "--input", json_path, "--uncovered-only")).to eq(0)
      expect(stdout.string).to eq("#{code_path}:3,6-8,10\n")
    end

    # The root is shown project-relative, and a root that has not been
    # expanded yet is still that root.
    it "trims an unexpanded root off the paths it sweeps" do
      allow(SimpleCov).to receive(:root).and_return(File.join(tmp, "lib", ".."))

      expect(run("show", "--input", json_path, "--uncovered-only")).to eq(0)
      expect(stdout.string).to eq("lib/code.rb:3,6-8,10\n")
    end

    it "notes a fully covered project under a bare --uncovered-only" do
      entry["lines"] = [1, 1, 1, nil, nil, 1, 1, 1, 1, 1]
      File.write(json_path, JSON.dump(payload))

      expect(run("show", "--input", json_path, "--uncovered-only")).to eq(0)
      expect(stdout.string).to be_empty
      expect(stderr.string).to eq("simplecov show: nothing uncovered\n")
    end

    it "emits the project sweep as JSON" do
      expect(run("show", "--input", json_path, "--json")).to eq(0)
      expect(JSON.parse(stdout.string)).to eq([{"path" => code_path, "missed" => [3, 6, 7, 8, 10]}])
    end

    it "notes a fully covered file under --uncovered-only instead of printing" do
      entry["lines"] = [1, 1, 1, nil, nil, 1, 1, 1, 1, 1]
      File.write(json_path, JSON.dump(payload))
      expect(run("show", "--input", json_path, "--uncovered-only", "lib/code.rb")).to eq(0)
      expect(stdout.string).to be_empty
      expect(stderr.string).to eq("simplecov show: nothing uncovered in lib/code.rb\n")
    end

    # Also the line-coverage-only shape: no branches or methods arrays.
    it "reads the source from disk when the report carries none" do
      entry.delete("source")
      entry.delete("branches")
      entry.delete("methods")
      File.write(json_path, JSON.dump(payload))
      FileUtils.mkdir_p(File.dirname(code_path))
      File.write(code_path, "#{source.join("\n")}\n")

      expect(run("show", "--input", json_path, "lib/code.rb")).to eq(0)
      expect(stdout.string).to include("  return 1 if rows.empty?")
      expect(stdout.string).not_to include("branch missed")
    end

    it "refuses a disk source that drifted from the report" do
      entry.delete("source")
      File.write(json_path, JSON.dump(payload))
      FileUtils.mkdir_p(File.dirname(code_path))
      File.write(code_path, "one\ntwo\n")

      expect(run("show", "--input", json_path, "lib/code.rb")).to eq(1)
      expect(stderr.string).to include("changed since the report")
    end

    it "errors when neither the report nor the disk has the source" do
      entry.delete("source")
      File.write(json_path, JSON.dump(payload))

      expect(run("show", "--input", json_path, "lib/code.rb")).to eq(1)
      expect(stderr.string).to include("regenerate")
    end

    it "errors on a report without line data" do
      entry.delete("lines")
      File.write(json_path, JSON.dump(payload))
      expect(run("show", "--input", json_path, "lib/code.rb")).to eq(1)
      expect(stderr.string).to eq("simplecov show: no line coverage for lib/code.rb in #{json_path}\n")
    end

    # A gutter is a list of counts. Something else under that key is no
    # more usable than nothing under it.
    it "errors on a report whose line data is no list" do
      entry["lines"] = "junk"
      File.write(json_path, JSON.dump(payload))
      expect(run("show", "--input", json_path, "lib/code.rb")).to eq(1)
      expect(stderr.string).to eq("simplecov show: no line coverage for lib/code.rb in #{json_path}\n")
    end

    it "reports an unknown file like the coverage subcommand does" do
      expect(run("show", "--input", json_path, "lib/nope.rb")).to eq(1)
      expect(stderr.string).to eq("simplecov show: no entry for lib/nope.rb in #{json_path}\n")
    end

    # One complaint, not two: the wrong-typed entry is reported and
    # nothing goes on to ask it for lines.
    it "reports a wrong-typed entry as invalid input" do
      File.write(json_path, JSON.dump("coverage" => {code_path => "junk"}))
      expect(run("show", "--input", json_path, "lib/code.rb")).to eq(1)
      expect(stderr.string).to eq(
        "simplecov show: input file #{json_path.inspect} isn't valid JSON " \
        "(entry for lib/code.rb must be an object)\n"
      )
    end

    it "errors without a path" do
      expect(run("show", "--input", json_path)).to eq(1)
      expect(stderr.string).to include("missing path")
    end

    it "colorizes counts and markers for a tty" do
      allow(SimpleCov::Color).to receive(:enabled?).and_return(true)
      expect(run("show", "--input", json_path, "lib/code.rb")).to eq(0)
      expect(stdout.string).to include("\e[31m").and include("\e[32m")
    end

    it "emits the annotation as JSON" do
      expect(run("show", "--input", json_path, "--json", "lib/code.rb")).to eq(0)
      parsed = JSON.parse(stdout.string)
      expect(parsed["path"]).to eq("lib/code.rb")
      expect(parsed["missed"]).to eq([3, 6, 7, 8, 10])
      expect(parsed["lines"].size).to eq(8)
      expect(parsed["lines"].first).to eq("number" => 1, "hits" => 1)
      expect(parsed["markers"]).to include("1" => ["method missed"], "2" => ["branch missed"], "3" => ["missed"])
    end

    # JSON mode reads only the coverage data, so it answers even when
    # neither the report nor the disk can produce the source text.
    it "answers JSON without any source available" do
      entry.delete("source")
      File.write(json_path, JSON.dump(payload))

      expect(run("show", "--input", json_path, "--json", "lib/code.rb")).to eq(0)
      expect(JSON.parse(stdout.string)["missed"]).to eq([3, 6, 7, 8, 10])
    end

    it_behaves_like "a --no-color subcommand" do
      let(:no_color_argv) { ["show", "--input", json_path, "--no-color", "lib/code.rb"] }
    end

    it "documents itself in the usage text" do
      expect(run("help")).to eq(0)
      expect(stdout.string).to include("show options:")
    end

    describe ".source_for" do
      # The report's lines have no newlines on them, so the source read
      # from disk in their place must not either.
      it "reads the file from disk without the newlines" do
        FileUtils.mkdir_p(File.dirname(code_path))
        File.write(code_path, source.join("\n") << "\n")
        entry.delete("source")

        read = SimpleCov::CLI::Show.source_for(code_path, entry, {path: "lib/code.rb", input: json_path}, stderr)
        expect(read).to eq(source)
      end
    end

    describe ".parse" do
      # Every other example passes --input, so the default is only ever
      # seen when nothing says otherwise.
      it "reads the project's own report when no input is named" do
        expect(SimpleCov::CLI::Show.parse([])[:input]).to eq(described_class.default_input)
      end

      # Numbered by where the count sits in the gutter, not by where it
      # lands in the answer.
      it "counts only whole numbers of hits as lines to report" do
        entry["lines"] = [1, 0.0, "3", nil, 5]
        File.write(json_path, JSON.dump(payload))

        expect(run("show", "--input", json_path, "--json", "lib/code.rb")).to eq(0)
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

      # One file is annotated, so anything past the first is not a path.
      it "takes the first bare argument as the path" do
        expect(SimpleCov::CLI::Show.parse(%w[lib/a.rb lib/b.rb])[:path]).to eq("lib/a.rb")
      end
    end

    it "reports a source list carrying something that is not a line" do
      entry["source"] = ["def call", 42]
      File.write(json_path, JSON.dump(payload))

      expect(run("show", "--input", json_path, "lib/code.rb")).to eq(1)
      expect(stderr.string).to include("no source for lib/code.rb")
    end

    # Source is a list of lines. One string holding the whole file is
    # not that, and is no more usable than none at all.
    it "reports a source that is not a list of lines" do
      entry["source"] = "def call\nend\n"
      File.write(json_path, JSON.dump(payload))

      expect(run("show", "--input", json_path, "lib/code.rb")).to eq(1)
      expect(stderr.string).to include("no source for lib/code.rb")
    end

    # The renderer asked directly, rather than through a whole report:
    # the gutter arithmetic and the tolerance for malformed entries are
    # what a rendered page can only show one combination of at a time.
    describe SimpleCov::CLI::Show::Annotator do
      let(:annotator) { described_class }
      let(:out) { StringIO.new }

      describe "#count_width" do
        it "measures the widest hit count" do
          expect(annotator.count_width({"lines" => [1, 100, 5]})).to eq(3)
        end

        it "ignores the lines carrying no count at all" do
          expect(annotator.count_width({"lines" => [nil, 7, nil]})).to eq(1)
        end

        # One column, so a countless file still lines its source up.
        it "falls back to a single column when nothing is counted" do
          expect(annotator.count_width({"lines" => [nil, nil]})).to eq(1)
          expect(annotator.count_width({"lines" => []})).to eq(1)
        end
      end

      describe "#missed_line_of" do
        it "reads a zero-hit item's reported line" do
          expect(annotator.missed_line_of({"report_line" => 4, "coverage" => 0})).to eq(4)
        end

        # report_line is what the report says to point at; start_line is
        # where the construct begins, and stands in when it is absent.
        it "prefers the reported line to the starting one" do
          expect(annotator.missed_line_of({"report_line" => 4, "start_line" => 9, "coverage" => 0})).to eq(4)
          expect(annotator.missed_line_of({"start_line" => 9, "coverage" => 0})).to eq(9)
        end

        it "passes over an item that was hit" do
          expect(annotator.missed_line_of({"report_line" => 4, "coverage" => 1})).to be_nil
        end

        it "passes over an item whose count is no count" do
          expect(annotator.missed_line_of({"report_line" => 4, "coverage" => nil})).to be_nil
          expect(annotator.missed_line_of({"report_line" => 4, "coverage" => "0"})).to be_nil
          expect(annotator.missed_line_of({"report_line" => 4})).to be_nil
        end

        it "passes over an item whose line is no line" do
          expect(annotator.missed_line_of({"report_line" => "4", "coverage" => 0})).to be_nil
          expect(annotator.missed_line_of({"coverage" => 0})).to be_nil
        end

        it "passes over anything that is not an item" do
          expect(annotator.missed_line_of("junk")).to be_nil
          expect(annotator.missed_line_of(nil)).to be_nil
          expect(annotator.missed_line_of([{"report_line" => 4, "coverage" => 0}])).to be_nil
        end
      end

      describe "#each_missed" do
        it "yields the line of every missed item and no other" do
          items = [{"report_line" => 2, "coverage" => 0}, {"report_line" => 3, "coverage" => 1},
                   {"report_line" => 5, "coverage" => 0}]
          expect { |probe| annotator.each_missed(items, &probe) }.to yield_successive_args(2, 5)
        end

        # A report without branches or methods carries nothing here, and
        # a malformed one carries the wrong thing.
        it "yields nothing when there is no list to walk" do
          expect { |probe| annotator.each_missed(nil, &probe) }.not_to yield_control
          expect { |probe| annotator.each_missed("junk", &probe) }.not_to yield_control
          expect { |probe| annotator.each_missed([], &probe) }.not_to yield_control
        end
      end

      describe "#missed_lines" do
        it "numbers the zero-hit lines from one" do
          expect(annotator.missed_lines({"lines" => [0, 1, 0, nil]})).to eq([1, 3])
        end

        it "passes over the lines that carry no count" do
          expect(annotator.missed_lines({"lines" => [nil, nil]})).to be_empty
        end

        # A count is a whole number of hits. A zero that is not one is
        # not a miss the gutter knows how to report.
        it "passes over a zero that is no count" do
          expect(annotator.missed_lines({"lines" => [0.0]})).to be_empty
        end
      end

      describe "#call" do
        # An embedded source can carry more lines than the report has
        # counts for. Those lines still print, with a blank gutter.
        it "leaves the gutter blank past the end of the counts" do
          annotator.call(%w[one two], {"lines" => [1], "branches" => [], "methods" => []}, out, color: false)
          expect(out.string).to eq("1  1  one\n2     two\n")
        end

        # The caret line is painted under the same rule as the count
        # beside it, so both answer to the one setting.
        it "paints the caret as well as the count" do
          annotator.call(%w[one], {"lines" => [0], "branches" => [], "methods" => []}, out, color: true)
          expect(out.string).to eq("1  \e[31m0\e[0m  one\n      \e[31m^ missed\e[0m\n")
        end
      end

      describe "#row" do
        let(:widths) { {number: 2, count: 3} }

        it "right-aligns the number and the count in their columns" do
          expect(annotator.row(7, 42, "code", widths, false)).to eq(" 7   42  code")
        end

        it "leaves the count column blank for a line that carries none" do
          expect(annotator.row(7, nil, "code", widths, false)).to eq(" 7       code")
        end

        # A count is a number. Anything else in the slot is not one, and
        # printing it would put a non-count in the count column.
        it "leaves the column blank for a count that is no number" do
          expect(annotator.row(7, "3", "code", widths, false)).to eq(" 7       code")
        end

        it "trims a row whose source line is empty" do
          expect(annotator.row(7, nil, "", widths, false)).to eq(" 7")
        end

        # Padded before painting, so the escape codes cannot widen the
        # column they sit in.
        it "paints a missed count red and a hit one green, after padding" do
          expect(annotator.row(7, 0, "code", widths, true)).to eq(" 7  \e[31m  0\e[0m  code")
          expect(annotator.row(7, 1, "code", widths, true)).to eq(" 7  \e[32m  1\e[0m  code")
        end

        it "leaves a blank count unpainted" do
          expect(annotator.row(7, nil, "code", widths, true)).to eq(" 7       code")
        end
      end

      describe "#emit" do
        let(:widths) { {number: 2, count: 3} }

        it "prints the row alone when nothing is missed on it" do
          annotator.emit(out, " 7   42  code", [], widths, false)
          expect(out.string).to eq(" 7   42  code\n")
        end

        # The caret sits under the source column, past the number, the
        # count, and the two-space gaps either side of it.
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
  end

  describe "affected subcommand", mutant_expression: "SimpleCov::CLI::Affected*" do
    # Built once and copied per example: see GitFixture.
    let(:fixture_files) do
      {
        "lib/result.rb" => "# original\n", "lib/quiet.rb" => "# original\n",
        "lib/odd.rb" => "# original\n", "lib/stale.rb" => "# original\n",
        "lib/plain.rb" => "# original\n", "toplevel_test.rb" => "# original\n",
        "lib/suffixless.rb" => "# original\n", "spec/no_suffix" => "# original\n",
        "lib/plain2.rb" => "# original\n", "spec/test_helper.rb" => "# original\n",
        "spec/result_spec.rb" => "# original\n", "spec/source_file_spec.rb" => "# original\n",
        "spec/helper.rb" => "# original\n", "Gemfile.lock" => "# original\n",
        ".gitignore" => "coverage.json\nout.txt\n"
      }
    end
    let(:tmp) { GitFixture.checkout(fixture_files) }
    let(:json_path) { File.join(tmp, "coverage.json") }
    let(:out_path) { File.join(tmp, "out.txt") }

    # Five contexts: two ordinary path:line tests touching result.rb, a
    # locationless Minitest fallback id touching odd.rb, a test whose
    # file no longer exists touching stale.rb, and a slashless top-level
    # test file. quiet.rb is covered but no recorded test executes it.
    let(:payload) do
      {
        "contexts" => [
          "spec/result_spec.rb:42",
          "spec/source_file_spec.rb:12",
          "OddTest#test_odd",
          "spec/ghost_spec.rb:7",
          "toplevel_test.rb:99",
          "spec/no_suffix:3"
        ],
        "coverage" => {
          File.join(tmp, "lib/result.rb") => {"lines" => [nil, 1, 2, 0], "contexts" => {"0" => "6", "1" => "4"}},
          File.join(tmp, "lib/quiet.rb") => {"lines" => [1, nil]},
          File.join(tmp, "lib/odd.rb") => {"lines" => [1], "contexts" => {"2" => "1"}},
          File.join(tmp, "lib/stale.rb") => {"lines" => [1], "contexts" => {"3" => "1"}},
          File.join(tmp, "lib/plain.rb") => {"lines" => [1], "contexts" => {"4" => "1"}},
          File.join(tmp, "lib/suffixless.rb") => {"lines" => [1], "contexts" => {"5" => "1"}},
          File.join(tmp, "lib/plain2.rb") => {"lines" => [1], "contexts" => {"4" => "1"}}
        }
      }
    end

    def file!(path, content = "# original\n")
      full = File.join(tmp, path)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, content)
    end

    def commit!(message)
      GitFixture.commit!(tmp, message)
    end

    def git_in_repo(*argv)
      system("git", "-C", tmp, *argv, exception: true)
    end

    before { File.write(json_path, JSON.dump(payload)) }

    # rm_rf rather than remove_entry: it shrugs off files a lingering
    # background git process deletes mid-walk instead of raising ENOENT.
    after { FileUtils.rm_rf(tmp) }

    def run_in_repo(*argv)
      Dir.chdir(tmp) { run(*argv) }
    end

    it "selects the test files whose recorded tests touch the changed code" do
      file!("lib/result.rb", "# changed\n")
      expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      expect(stdout.string).to eq("spec/result_spec.rb\nspec/source_file_spec.rb\n")
      expect(stderr.string).to be_empty
    end

    it "always selects a changed test file itself" do
      file!("spec/result_spec.rb", "# changed\n")
      expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      expect(stdout.string).to eq("spec/result_spec.rb\n")
      expect(stderr.string).to be_empty
    end

    it "always selects a new test file the map has never seen" do
      file!("spec/brand_new_spec.rb")
      expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      expect(stdout.string).to eq("spec/brand_new_spec.rb\n")
      expect(stderr.string).to be_empty
    end

    it "answers an empty selection, with a note, when no recorded test touches the change" do
      file!("lib/quiet.rb", "# changed\n")
      expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      expect(stdout.string).to be_empty
      expect(stderr.string).to eq("simplecov affected: no recorded test touches the changed code\n")
    end

    it "notes when nothing differs from the base" do
      expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      expect(stdout.string).to be_empty
      expect(stderr.string).to eq("simplecov affected: no changes against main\n")
    end

    # A repository whose default branch is trunk (or master) works
    # bare: the omitted --base resolves through origin's HEAD.
    it "defaults the base to the branch origin's HEAD points at" do
      system("git", "-C", tmp, "branch", "-m", "main", "trunk", exception: true)
      system("git", "-C", tmp, "update-ref", "refs/remotes/origin/trunk", "HEAD", exception: true)
      system("git", "-C", tmp, "symbolic-ref", "refs/remotes/origin/HEAD",
             "refs/remotes/origin/trunk", exception: true)

      expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      expect(stderr.string).to eq("simplecov affected: no changes against trunk\n")
    end

    it "still emits a JSON object when nothing differs from the base" do
      expect(run_in_repo("affected", "--input", json_path, "--json")).to eq(0)
      expect(JSON.parse(stdout.string)).to eq("full_suite" => false, "triggers" => [], "tests" => [])
    end

    it "drops a deleted test file the map never knew without a note" do
      file!("spec/unrecorded_spec.rb")
      commit!("add unrecorded spec")
      File.delete(File.join(tmp, "spec/unrecorded_spec.rb"))
      expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      expect(stdout.string).to be_empty
      expect(stderr.string).to eq("simplecov affected: no recorded test touches the changed code\n")
    end

    it "diffs against the ref given with --base" do
      file!("lib/result.rb", "# changed\n")
      commit!("change result")
      expect(run_in_repo("affected", "--input", json_path, "--base", "HEAD~1")).to eq(0)
      expect(stdout.string).to eq("spec/result_spec.rb\nspec/source_file_spec.rb\n")
    end

    # --merge-base semantics: the base advancing after the branch point
    # must not read as part of this change, while uncommitted work must.
    it "ignores commits that landed on the base after the branch point" do
      system("git", "-C", tmp, "switch", "-qc", "feature", exception: true)
      system("git", "-C", tmp, "switch", "-q", "main", exception: true)
      file!("lib/quiet.rb", "# changed on main\n")
      commit!("change quiet on main")
      system("git", "-C", tmp, "switch", "-q", "feature", exception: true)
      file!("lib/result.rb", "# changed\n")
      expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      expect(stdout.string).to eq("spec/result_spec.rb\nspec/source_file_spec.rb\n")
      expect(stderr.string).to be_empty
    end

    it "selects across the whole change from a subdirectory" do
      file!("lib/result.rb", "# changed\n")
      expect(Dir.chdir(File.join(tmp, "spec")) { run("affected", "--input", json_path) }).to eq(0)
      expect(stdout.string).to eq("spec/result_spec.rb\nspec/source_file_spec.rb\n")
      expect(stderr.string).to be_empty
    end

    it "starts the runner at the repository root" do
      file!("lib/result.rb", "# changed\n")
      script = "File.write(#{out_path.inspect}, Dir.pwd)"
      status = Dir.chdir(File.join(tmp, "spec")) do
        run("affected", "--input", json_path, "--run", RbConfig.ruby, "-e", script)
      end
      expect(status).to eq(0)
      expect(File.read(out_path)).to eq(File.realpath(tmp))
    end

    it "resolves changed files exactly instead of by suffix" do
      # The report carries only a lookalike key that merely ends with the
      # changed path; a suffix match would select that entry's tests as
      # if they covered lib/result.rb.
      payload["coverage"].delete(File.join(tmp, "lib/result.rb"))
      payload["coverage"]["/elsewhere/lib/result.rb"] = {"lines" => [1], "contexts" => {"0" => "1"}}
      File.write(json_path, JSON.dump(payload))
      file!("lib/result.rb", "# changed\n")

      expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      expect(stdout.string).to be_empty
      expect(stderr.string).to include("lib/result.rb changed but").and include("falling back to the full suite")
    end

    it "resolves a report keyed by relative paths, from a subdirectory too" do
      payload["coverage"] = payload["coverage"].transform_keys { |key| key.delete_prefix("#{tmp}/") }
      File.write(json_path, JSON.dump(payload))
      file!("lib/result.rb", "# changed\n")

      expect(Dir.chdir(File.join(tmp, "spec")) { run("affected", "--input", json_path) }).to eq(0)
      expect(stdout.string).to eq("spec/result_spec.rb\nspec/source_file_spec.rb\n")
    end

    it "errors outside a git working tree" do
      Dir.mktmpdir("simplecov-cli-affected-plain-") do |plain|
        expect(Dir.chdir(plain) { run("affected", "--input", json_path) }).to eq(1)
      end
      expect(stdout.string).to be_empty
      expect(stderr.string).to eq("simplecov affected: not inside a git working tree\n")
    end

    # A report with no "coverage" key at all covers nothing, which is
    # not the same as a report whose "coverage" is the wrong shape.
    it "selects nothing from a report that carries no coverage" do
      payload.delete("coverage")
      File.write(json_path, JSON.dump(payload))
      file!("lib/result.rb", "# changed\n")

      expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      expect(stderr.string).to include("has no data for it").and include("falling back to the full suite")
    end

    it "refuses a report whose coverage is the wrong shape" do
      payload["coverage"] = []
      File.write(json_path, JSON.dump(payload))
      file!("lib/result.rb", "# changed\n")

      expect(run_in_repo("affected", "--input", json_path)).to eq(1)
      expect(stderr.string).to eq(
        %(simplecov affected: input file #{json_path.inspect} isn't valid JSON ("coverage" must be an object)\n)
      )
    end

    # A recorded id names a file when it has a directory or a .rb suffix.
    # "toplevel_test.rb:99" has no slash, so only the suffix answers for
    # it, and a bare test file at the root is a real shape.
    it "selects a recorded test file that sits at the repository root" do
      file!("lib/plain.rb", "# changed\n")

      expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      expect(stdout.string).to eq("toplevel_test.rb\n")
      expect(stderr.string).to be_empty
    end

    describe ".parse" do
      it "starts with no base, no runner, and both compact forms off" do
        expect(SimpleCov::CLI::Affected.parse([]))
          .to eq(input: described_class.default_input, json: false, no_color: false,
                 base: nil, run: nil, rest: [])
      end

      # Everything after --run is the runner command, verbatim, so the
      # command's own flags never collide with ours.
      it "splits the runner command off at --run" do
        opts = SimpleCov::CLI::Affected.parse(%w[--base main --run rake test --verbose])
        expect(opts).to include(base: "main", run: %w[rake test --verbose], rest: [])
      end

      it "leaves an empty runner command empty rather than absent" do
        expect(SimpleCov::CLI::Affected.parse(%w[--run])).to include(run: [])
      end

      # The pair itself, since a head with no --run still has to answer
      # with two values for the caller to destructure.
      it "answers a head and no runner when there is no --run" do
        expect(SimpleCov::CLI::Affected.split_runner(%w[--base main])).to eq([%w[--base main], nil])
      end

      it "answers the head and the runner when there is one" do
        expect(SimpleCov::CLI::Affected.split_runner(%w[--base main --run rake])).to eq([%w[--base main], %w[rake]])
      end
    end

    # Two of them, so the message names the first rather than whichever
    # happens to be there.
    it "names the first stray positional, not the last" do
      expect(run_in_repo("affected", "--input", json_path, "feature-x", "feature-y")).to eq(1)
      expect(stderr.string)
        .to eq(%(simplecov affected: unexpected argument "feature-x" (did you mean `--base feature-x`?)\n))
    end

    it "reports a missing input, naming itself and the file" do
      missing = File.join(tmp, "nope.json")

      expect(run_in_repo("affected", "--input", missing)).to eq(1)
      expect(stderr.string).to eq("simplecov affected: #{missing} not found\n")
    end

    it "reports an input that is not JSON at all" do
      File.write(json_path, "not json")

      expect(run_in_repo("affected", "--input", json_path)).to eq(1)
      expect(stderr.string).to start_with(%(simplecov affected: input file #{json_path.inspect} isn't valid JSON))
    end

    # A recorded id names a file when it has a directory OR a .rb suffix.
    # "spec/no_suffix" has the directory and not the suffix, so only the
    # first half of that answers for it.
    it "selects a recorded test file that carries no .rb suffix" do
      file!("lib/suffixless.rb", "# changed\n")

      expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      expect(stdout.string).to eq("spec/no_suffix\n")
      expect(stderr.string).to be_empty
    end

    # Two changed files whose recorded tests are the same file: it runs
    # once, and the list comes back sorted rather than in the order the
    # changes happened to arrive.
    it "names each selected test file once, in order" do
      file!("lib/plain.rb", "# changed\n")
      file!("lib/plain2.rb", "# changed\n")
      file!("lib/result.rb", "# changed\n")

      expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      expect(stdout.string).to eq("spec/result_spec.rb\nspec/source_file_spec.rb\ntoplevel_test.rb\n")
    end

    it "emits no tests under --json when the whole suite runs" do
      file!("lib/result.rb", "# changed\n")
      file!("lib/stale.rb", "# changed\n")

      expect(run_in_repo("affected", "--input", json_path, "--json")).to eq(0)
      parsed = JSON.parse(stdout.string)
      expect(parsed["full_suite"]).to be true
      expect(parsed["tests"]).to be_empty
    end

    it "names the command it could not run for the full suite too" do
      file!("Gemfile.lock", "# changed\n")
      missing = File.join(tmp, "nope-does-not-exist")

      expect(run_in_repo("affected", "--input", json_path, "--run", missing)).to eq(127)
      # JRuby's spawn reports a missing command through the child's exit
      # status instead of raising, so there is no message to look for.
      unless RUBY_ENGINE == "jruby"
        expect(stderr.string).to include("cannot run #{missing.inspect} (No such file or directory")
      end
    end

    # --merge-base, so commits that landed on the base after the branch
    # point stay out of the change.
    it "diffs against the merge base, not the base's tip" do
      git_in_repo("checkout", "-q", "-b", "feature")
      file!("lib/result.rb", "# changed\n")
      commit!("change on the branch")
      git_in_repo("checkout", "-q", "main")
      file!("lib/plain.rb", "# changed on main\n")
      commit!("change on main")
      git_in_repo("checkout", "-q", "feature")

      expect(run_in_repo("affected", "--input", json_path, "--base", "main")).to eq(0)
      expect(stdout.string).to eq("spec/result_spec.rb\nspec/source_file_spec.rb\n")
    end

    it "relays what git said about a base it cannot resolve" do
      expect(run_in_repo("affected", "--input", json_path, "--base", "no-such-ref")).to eq(1)
      expect(stderr.string).to start_with("simplecov affected: `git diff` failed: ")
      expect(stderr.string.lines.size).to eq(1)
    end

    # The name is judged on the basename: "spec/test_helper.rb" starts
    # with no "test_" and ends with no "_spec.rb", so only its last
    # component says it is a test file at all.
    it "recognises a test file by its own name, not by its path" do
      file!("spec/test_helper.rb", "# changed\n")

      expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      expect(stdout.string).to eq("spec/test_helper.rb\n")
      expect(stderr.string).to be_empty
    end

    # An index past the end of the recorded contexts names a test that
    # is not there, which makes the table malformed rather than partly
    # usable.
    it "refuses a contexts table that indexes past the recorded tests" do
      payload["coverage"][File.join(tmp, "lib/result.rb")] = {"lines" => [1], "contexts" => {"7" => "1"}}
      File.write(json_path, JSON.dump(payload))
      file!("lib/result.rb", "# changed\n")

      expect(run_in_repo("affected", "--input", json_path)).to eq(1)
      expect(stderr.string).to eq(
        "simplecov affected: input file #{json_path.inspect} isn't valid JSON " \
        "(entry for lib/result.rb carries a malformed \"contexts\" table)\n"
      )
    end

    # `--`, so a base ref that is also the name of a file in the tree is
    # read as the ref it is rather than as a path to limit the diff to.
    # Without the separator git calls it ambiguous and refuses.
    it "diffs against a base ref that is also a path in the tree" do
      git_in_repo("branch", "lib/quiet.rb")
      git_in_repo("checkout", "-q", "-b", "feature")
      file!("lib/result.rb", "# changed\n")

      expect(run_in_repo("affected", "--input", json_path, "--base", "lib/quiet.rb")).to eq(0)
      expect(stdout.string).to eq("spec/result_spec.rb\nspec/source_file_spec.rb\n")
      expect(stderr.string).to be_empty
    end

    # A file dropped from the index but still on disk is both a deletion
    # in the diff and an untracked file, so it arrives twice. It is one
    # change, and the trigger it raises is one trigger.
    it "names a file that is both changed and untracked only once" do
      git_in_repo("rm", "--cached", "-q", "Gemfile.lock")

      expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      expect(stderr.string.scan("Gemfile.lock changed but").size).to eq(1)
    end

    # The diff itself failing to run, rather than the toplevel lookup
    # that precedes it: one complaint, not two.
    it "reports a git that cannot run the diff, once" do
      allow(SimpleCov::CLI::Git).to receive(:capture).and_wrap_original do |original, *argv|
        argv.include?("diff") ? [nil, "No such file or directory", false] : original.call(*argv)
      end
      file!("lib/result.rb", "# changed\n")

      expect(run_in_repo("affected", "--input", json_path)).to eq(1)
      expect(stderr.string).to eq("simplecov affected: cannot run git (No such file or directory)\n")
    end

    it "reports a git it cannot run at all, once" do
      allow(SimpleCov::CLI::Git).to receive(:capture).and_return([nil, "No such file or directory", false])

      expect(run_in_repo("affected", "--input", json_path)).to eq(1)
      expect(stderr.string).to eq("simplecov affected: cannot run git (No such file or directory)\n")
    end

    it "rejects a stray positional that looks like a forgotten --base" do
      expect(run_in_repo("affected", "--input", json_path, "feature-x")).to eq(1)
      expect(stdout.string).to be_empty
      expect(stderr.string)
        .to eq(%(simplecov affected: unexpected argument "feature-x" (did you mean `--base feature-x`?)\n))
    end

    it "refuses a base ref that would read as a git option" do
      expect(run_in_repo("affected", "--input", json_path, "--base=--output=evil")).to eq(1)
      expect(stdout.string).to be_empty
      expect(stderr.string).to eq(%(simplecov affected: invalid base ref "--output=evil"\n))
    end

    it "falls back to the full suite when a changed file has no coverage data" do
      file!("Gemfile.lock", "# changed\n")
      file!("lib/result.rb", "# changed\n")
      expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      expect(stdout.string).to be_empty
      expect(stderr.string).to include("Gemfile.lock changed but #{json_path} has no data for it")
      expect(stderr.string).to include("falling back to the full suite")
    end

    it "treats a changed spec helper as outside the tracked set" do
      file!("spec/helper.rb", "# changed\n")
      expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      expect(stdout.string).to be_empty
      expect(stderr.string).to include("spec/helper.rb changed but")
      expect(stderr.string).to include("falling back to the full suite")
    end

    it "falls back when a recorded test touching the change has no file location" do
      file!("lib/odd.rb", "# changed\n")
      expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      expect(stdout.string).to be_empty
      expect(stderr.string).to include(
        "simplecov affected: recorded test OddTest#test_odd touches lib/odd.rb but has no file location"
      )
      expect(stderr.string).to include("falling back to the full suite")
    end

    it "falls back when the map names a test file that no longer exists" do
      file!("lib/stale.rb", "# changed\n")
      expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      expect(stdout.string).to be_empty
      expect(stderr.string)
        .to include("simplecov affected: recorded test file spec/ghost_spec.rb no longer exists")
      expect(stderr.string).to include("falling back to the full suite")
    end

    it "drops a test file deleted by the change instead of falling back" do
      File.delete(File.join(tmp, "spec/source_file_spec.rb"))
      file!("lib/result.rb", "# changed\n")
      expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      expect(stdout.string).to eq("spec/result_spec.rb\n")
      expect(stderr.string).to include("skipping deleted test file spec/source_file_spec.rb")
      expect(stderr.string).not_to include("full suite")
    end

    it "emits the selection as a JSON object under --json" do
      file!("lib/result.rb", "# changed\n")
      expect(run_in_repo("affected", "--input", json_path, "--json")).to eq(0)
      expect(JSON.parse(stdout.string)).to eq(
        "full_suite" => false, "triggers" => [], "tests" => ["spec/result_spec.rb", "spec/source_file_spec.rb"]
      )
    end

    it "carries the triggers in the JSON fallback answer" do
      file!("Gemfile.lock", "# changed\n")
      expect(run_in_repo("affected", "--input", json_path, "--json")).to eq(0)
      parsed = JSON.parse(stdout.string)
      expect(parsed["full_suite"]).to be(true)
      expect(parsed["tests"]).to eq([])
      expect(parsed["triggers"].join).to include("Gemfile.lock")
    end

    it "hands the selection to the runner under --run" do
      file!("lib/result.rb", "# changed\n")
      script = "File.write(#{out_path.inspect}, ARGV.join(' '))"
      expect(run_in_repo("affected", "--input", json_path, "--run", RbConfig.ruby, "-e", script)).to eq(0)
      expect(File.read(out_path)).to eq("spec/result_spec.rb spec/source_file_spec.rb")
      expect(stderr.string).to include("running 2 test files")
    end

    it "runs the command bare when falling back to the full suite" do
      file!("Gemfile.lock", "# changed\n")
      script = "File.write(#{out_path.inspect}, ARGV.join(' ').inspect)"
      expect(run_in_repo("affected", "--input", json_path, "--run", RbConfig.ruby, "-e", script)).to eq(0)
      expect(File.read(out_path)).to eq('""')
      expect(stderr.string).to include("falling back to the full suite")
    end

    # A trigger forces the full suite even when files were also
    # selected, and the bare run is the whole answer: appending the
    # selection to it would run those files a second time.
    it "runs the command bare, and only bare, when a trigger fires alongside a selection" do
      file!("lib/result.rb", "# changed\n")
      file!("lib/stale.rb", "# changed\n")
      script = "File.write(#{out_path.inspect}, ARGV.join(' ').inspect)"

      expect(run_in_repo("affected", "--input", json_path, "--run", RbConfig.ruby, "-e", script)).to eq(0)
      expect(File.read(out_path)).to eq('""')
      expect(stderr.string).to include("no longer exists").and include("falling back to the full suite")
    end

    it "names the command it could not run" do
      file!("lib/result.rb", "# changed\n")
      missing = File.join(tmp, "nope-does-not-exist")

      expect(run_in_repo("affected", "--input", json_path, "--run", missing)).to eq(127)
      # JRuby's spawn reports a missing command through the child's exit
      # status instead of raising, so there is no message to look for.
      expect(stderr.string).to include("cannot run #{missing.inspect}") unless RUBY_ENGINE == "jruby"
    end

    it "propagates the runner's exit status" do
      file!("lib/result.rb", "# changed\n")
      expect(run_in_repo("affected", "--input", json_path, "--run", RbConfig.ruby, "-e", "exit 3")).to eq(3)
    end

    it "speaks of one selected file in the singular" do
      file!("spec/result_spec.rb", "# changed\n")
      expect(run_in_repo("affected", "--input", json_path, "--run", RbConfig.ruby, "-e", "exit 0")).to eq(0)
      expect(stderr.string).to include("running 1 test file\n")
    end

    it "exits non-zero for a runner killed by a signal" do
      skip "SIGKILL semantics are POSIX; Windows reports an exit status instead" if Gem.win_platform?

      file!("lib/result.rb", "# changed\n")
      script = "Process.kill(:KILL, Process.pid)"
      expect(run_in_repo("affected", "--input", json_path, "--run", RbConfig.ruby, "-e", script)).to eq(1)
    end

    it "skips the runner when nothing is selected" do
      file!("lib/quiet.rb", "# changed\n")
      script = "File.write(#{out_path.inspect}, 'ran')"
      expect(run_in_repo("affected", "--input", json_path, "--run", RbConfig.ruby, "-e", script)).to eq(0)
      expect(File.exist?(out_path)).to be(false)
      expect(stderr.string).to include("no recorded test touches the changed code")
    end

    it "reports an unrunnable command like the run subcommand does" do
      file!("lib/result.rb", "# changed\n")
      expect(run_in_repo("affected", "--input", json_path, "--run", "definitely-not-a-command-xyz")).to eq(127)
      # JRuby's spawn doesn't raise for a missing command; the child
      # fails on its own, so only the 127 reaches us there.
      expect(stderr.string).to include("definitely-not-a-command-xyz") unless RUBY_ENGINE == "jruby"
    end

    it "reports a missing command after --run" do
      expect(run_in_repo("affected", "--input", json_path, "--run")).to eq(1)
      expect(stderr.string).to include("missing command after --run")
    end

    it "refuses to combine --run with --json" do
      expect(run_in_repo("affected", "--input", json_path, "--json", "--run", "true")).to eq(1)
      expect(stderr.string).to include("--json")
    end

    it "reports a bad base ref as a git error" do
      expect(run_in_repo("affected", "--input", json_path, "--base", "no-such-ref")).to eq(1)
      expect(stdout.string).to be_empty
      expect(stderr.string).to include("git diff")
    end

    it "explains what to enable when the document carries no contexts" do
      File.write(json_path, JSON.dump({"coverage" => {}}))
      file!("lib/result.rb", "# changed\n")
      expect(run_in_repo("affected", "--input", json_path)).to eq(1)
      expect(stderr.string).to include("track_tests")
    end

    it "treats a malformed per-file contexts table as invalid input" do
      [{"9" => "6"}, "junk"].each do |malformed|
        payload["coverage"][File.join(tmp, "lib/result.rb")]["contexts"] = malformed
        File.write(json_path, JSON.dump(payload))
        file!("lib/result.rb", "# changed\n")
        stderr.truncate(0) && stderr.rewind
        expect(run_in_repo("affected", "--input", json_path)).to eq(1), "expected 1 for #{malformed.inspect}"
        expect(stderr.string).to include("isn't valid")
      end
    end

    it "treats a wrong-typed entry as invalid input" do
      payload["coverage"][File.join(tmp, "lib/result.rb")] = "junk"
      File.write(json_path, JSON.dump(payload))
      file!("lib/result.rb", "# changed\n")
      expect(run_in_repo("affected", "--input", json_path)).to eq(1)
      expect(stderr.string).to eq(
        "simplecov affected: input file #{json_path.inspect} isn't valid JSON " \
        "(entry for lib/result.rb must be an object)\n"
      )
    end

    it "treats a non-object coverage section as invalid input" do
      File.write(json_path, JSON.dump(payload.merge("coverage" => "junk")))
      file!("lib/result.rb", "# changed\n")
      expect(run_in_repo("affected", "--input", json_path)).to eq(1)
      expect(stderr.string).to include('"coverage" must be an object')
    end

    it "reports a git failure while listing untracked files" do
      failed = instance_double(Process::Status, success?: false)
      allow(Open3).to receive(:capture3).and_call_original
      allow(Open3).to receive(:capture3)
        .with("git", "-C", anything, "ls-files", any_args).and_return(["", "boom\n", failed])
      file!("lib/result.rb", "# changed\n")
      expect(run_in_repo("affected", "--input", json_path)).to eq(1)
      expect(stderr.string).to include("`git ls-files` failed: boom")
    end

    it "reports git being unrunnable" do
      allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT, "git")
      expect(run_in_repo("affected", "--input", json_path)).to eq(1)
      expect(stderr.string).to include("cannot run git")
    end

    it "reports git vanishing between the root lookup and the diff" do
      allow(Open3).to receive(:capture3).and_call_original
      allow(Open3).to receive(:capture3)
        .with("git", "-C", anything, "diff", any_args).and_raise(Errno::ENOENT, "git")
      expect(run_in_repo("affected", "--input", json_path)).to eq(1)
      expect(stderr.string).to include("cannot run git")
    end

    it "documents itself in the usage text" do
      expect(run("help")).to eq(0)
      expect(stdout.string).to include("affected options:")
    end
  end

  describe "uncovered subcommand", mutant_expression: "SimpleCov::CLI::Uncovered*" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-uncovered-spec-") }
    let(:json_path) { File.join(tmp, "coverage.json") }

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

    it "lists files below 100% by default, worst-first" do
      expect(run("uncovered", "--input", json_path)).to eq(0)
      lines = stdout.string.lines.map(&:strip)
      expect(lines.size).to eq(2)
      expect(lines.first).to include("/abs/lib/c.rb")
      expect(lines.last).to include("/abs/lib/b.rb")
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

      it "appends the missed line ranges to each row" do
        expect(run("uncovered", "--input", json_path, "--missing")).to eq(0)
        expect(stdout.string).to include("/abs/lib/b.rb  missing 2-4,6")
        expect(stdout.string.lines.find { |line| line.include?("stats_only") }).not_to include("missing")
      end

      it "follows the chosen criterion" do
        expect(run("uncovered", "--input", json_path, "--missing", "--criterion", "branch")).to eq(0)
        expect(stdout.string).to include("/abs/lib/b.rb  missing 2")
      end

      it "reports the lines missed methods start on" do
        expect(run("uncovered", "--input", json_path, "--missing", "--criterion", "method")).to eq(0)
        expect(stdout.string).to include("/abs/lib/b.rb  missing 9")
      end

      it "adds the missed lines to the JSON rows" do
        expect(run("uncovered", "--input", json_path, "--missing", "--json")).to eq(0)
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

      it "emits one workflow warning per contiguous missed range" do
        expect(run("uncovered", "--input", json_path, "--annotate", "github")).to eq(0)
        expect(stdout.string).to eq(<<~OUT)
          ::warning file=/abs/lib/b.rb,line=2,endLine=4::Not covered by tests
          ::warning file=/abs/lib/b.rb,line=6,endLine=6::Not covered by tests
          ::warning file=lib/rooted.rb,line=2,endLine=2::Not covered by tests
        OUT
      end

      it "stays silent when nothing is below the threshold" do
        expect(run("uncovered", "--input", json_path, "--annotate", "github", "--threshold", "0")).to eq(0)
        expect(stdout.string).to be_empty
      end

      it "rejects an unknown annotation format" do
        expect(run("uncovered", "--input", json_path, "--annotate", "gitlab")).to eq(1)
        expect(stderr.string).to eq(%(simplecov uncovered: unknown --annotate "gitlab" (only github is supported)\n))
      end

      it "refuses to combine --annotate with --json" do
        expect(run("uncovered", "--input", json_path, "--annotate", "github", "--json")).to eq(1)
        expect(stderr.string).to include("--json")
      end
    end

    # Counts arrive from JSON, which carries numbers as whatever wrote
    # them. A row's covered and total columns are whole counts.
    it "counts a float covered and total as whole numbers" do
      File.write(json_path, JSON.dump(
                              "coverage" => {
                                "/abs/lib/b.rb" => {
                                  "total_lines" => 4.0, "covered_lines" => 2.0, "lines_covered_percent" => 50.0
                                }
                              }
                            ))

      expect(run("uncovered", "--input", json_path)).to eq(0)
      expect(stdout.string.strip).to eq("50.00%  2/4  /abs/lib/b.rb")
    end

    # JSON carries the counts through unformatted, so that is where a
    # float total shows if it was never made whole.
    it "carries whole counts into the JSON rows" do
      File.write(json_path, JSON.dump(
                              "coverage" => {
                                "/abs/lib/b.rb" => {
                                  "total_lines" => 4.0, "covered_lines" => 2.0, "lines_covered_percent" => 50.25
                                }
                              }
                            ))

      expect(run("uncovered", "--input", json_path, "--json")).to eq(0)
      row = JSON.parse(stdout.string).first
      expect(row["covered"]).to be(2)
      expect(row["total"]).to be(4)
      expect(row["percent"]).to be(50.25)
    end

    # A percent the report leaves out is no percent, and reads as none.
    it "counts an absent percent as none" do
      File.write(json_path, JSON.dump(
                              "coverage" => {"/abs/lib/b.rb" => {"total_lines" => 4, "covered_lines" => 2}}
                            ))

      expect(run("uncovered", "--input", json_path)).to eq(0)
      expect(stdout.string.strip).to eq("0.00%  2/4  /abs/lib/b.rb")
    end

    # A percent the report wrote as a whole number is still a percent.
    it "carries a whole-number percent as a fraction" do
      File.write(json_path, JSON.dump(
                              "coverage" => {
                                "/abs/lib/b.rb" => {
                                  "total_lines" => 4, "covered_lines" => 2, "lines_covered_percent" => 50
                                }
                              }
                            ))

      expect(run("uncovered", "--input", json_path, "--json")).to eq(0)
      expect(JSON.parse(stdout.string).first["percent"]).to be(50.0)
    end

    # Counts are read as far as they are numbers. A report written by
    # something else may carry them as text, and a row is still better
    # than a crash.
    it "reads a count that carries trailing text as far as it is a number" do
      File.write(json_path, JSON.dump(
                              "coverage" => {
                                "/abs/lib/b.rb" => {
                                  "total_lines" => "10 lines", "covered_lines" => "2 lines",
                                  "lines_covered_percent" => 20.0
                                }
                              }
                            ))

      expect(run("uncovered", "--input", json_path)).to eq(0)
      expect(stdout.string.strip).to eq("20.00%  2/10  /abs/lib/b.rb")
    end

    # No --missing, so the rows carry no missed-line column even for a
    # file whose line data would fill one.
    it "leaves the missed lines out of the rows unless they are asked for" do
      expect(run("uncovered", "--input", json_path)).to eq(0)
      expect(stdout.string).to include("/abs/lib/c.rb")
      expect(stdout.string).not_to include("missing")
    end

    it "leaves the missed lines out of the JSON rows too" do
      expect(run("uncovered", "--input", json_path, "--json")).to eq(0)
      expect(JSON.parse(stdout.string).map(&:keys).flatten.uniq)
        .to contain_exactly("file", "percent", "covered", "total")
    end

    # The worst files first, so a cap keeps the worst rather than the
    # best.
    it "keeps the worst files when --top caps the list" do
      expect(run("uncovered", "--input", json_path, "--top", "1")).to eq(0)
      expect(stdout.string.strip).to end_with("/abs/lib/c.rb")
    end

    # Counts arrive from JSON as whatever wrote them, a string included.
    it "counts a string covered and total as whole numbers" do
      File.write(json_path, JSON.dump(
                              "coverage" => {
                                "/abs/lib/b.rb" => {
                                  "total_lines" => "4", "covered_lines" => "2", "lines_covered_percent" => 50.0
                                }
                              }
                            ))

      expect(run("uncovered", "--input", json_path)).to eq(0)
      expect(stdout.string.strip).to eq("50.00%  2/4  /abs/lib/b.rb")
    end

    # An entry that is not an object has no counts to rank it by. A
    # list is the discriminating shape: a String answers nil to a string
    # key where a list refuses one outright.
    it "passes over an entry that is not an object" do
      File.write(json_path, JSON.dump("coverage" => {"/abs/lib/b.rb" => "junk", "/abs/lib/c.rb" => [1, 2]}))

      expect(run("uncovered", "--input", json_path)).to eq(0)
      expect(stdout.string).to eq("simplecov uncovered: nothing to report\n")
    end

    # A count the report omits is no count, and reads as zero.
    it "counts an absent covered figure as none" do
      File.write(json_path, JSON.dump(
                              "coverage" => {"/abs/lib/b.rb" => {"total_lines" => 4, "lines_covered_percent" => 0.0}}
                            ))

      expect(run("uncovered", "--input", json_path)).to eq(0)
      expect(stdout.string.strip).to eq("0.00%  0/4  /abs/lib/b.rb")
    end

    # Line data is a list of counts. Anything else under that key is no
    # more usable than nothing.
    it "reports no missed lines for line data that is not a list" do
      File.write(json_path, JSON.dump(
                              "coverage" => {
                                "/abs/lib/b.rb" => {
                                  "total_lines" => 4, "covered_lines" => 2,
                                  "lines_covered_percent" => 50.0, "lines" => "junk"
                                }
                              }
                            ))

      expect(run("uncovered", "--input", json_path, "--missing")).to eq(0)
      expect(stdout.string).not_to include("missing")
    end

    # The missed lines a criterion reports arrive per branch or method,
    # in the order the report lists them, and one line can carry more
    # than one of either.
    it "lists each missed line once, in order" do
      File.write(json_path, JSON.dump(
                              "coverage" => {
                                "/abs/lib/b.rb" => {
                                  "total_branches" => 4, "covered_branches" => 0,
                                  "branches_covered_percent" => 0.0,
                                  "branches" => [{"report_line" => 7, "coverage" => 0},
                                                 {"report_line" => 2, "coverage" => 0},
                                                 {"report_line" => 7, "coverage" => 0}]
                                }
                              }
                            ))

      expect(run("uncovered", "--input", json_path, "--missing", "--criterion", "branch")).to eq(0)
      expect(stdout.string.strip).to end_with("missing 2,7")
    end

    # A payload the criterion has no data in at all.
    it "reports no missed lines for a criterion the entry omits" do
      File.write(json_path, JSON.dump(
                              "coverage" => {
                                "/abs/lib/b.rb" => {
                                  "total_branches" => 2, "covered_branches" => 0, "branches_covered_percent" => 0.0
                                }
                              }
                            ))

      expect(run("uncovered", "--input", json_path, "--missing", "--criterion", "branch")).to eq(0)
      expect(stdout.string).not_to include("missing")
    end

    it "reports no missed lines for a method criterion the entry omits" do
      File.write(json_path, JSON.dump(
                              "coverage" => {
                                "/abs/lib/b.rb" => {
                                  "total_methods" => 2, "covered_methods" => 0, "methods_covered_percent" => 0.0
                                }
                              }
                            ))

      expect(run("uncovered", "--input", json_path, "--missing", "--criterion", "method")).to eq(0)
      expect(stdout.string).not_to include("missing")
    end

    # No missed lines at all is still an answer, and the JSON row says
    # so rather than leaving the key out.
    it "carries an empty missing list for line data it cannot read" do
      File.write(json_path, JSON.dump(
                              "coverage" => {
                                "/abs/lib/b.rb" => {
                                  "total_lines" => 4, "covered_lines" => 2,
                                  "lines_covered_percent" => 50.0, "lines" => "junk"
                                }
                              }
                            ))

      expect(run("uncovered", "--input", json_path, "--missing", "--json")).to eq(0)
      expect(JSON.parse(stdout.string).first["missing"]).to eq([])
    end

    # Paths are shown project-relative, and a root that has not been
    # expanded yet is still that root.
    it "trims an unexpanded root off the annotated paths" do
      allow(SimpleCov).to receive(:root).and_return(File.join(tmp, "lib", ".."))
      File.write(json_path, JSON.dump(
                              "coverage" => {
                                File.join(tmp, "lib/b.rb") => {
                                  "total_lines" => 2, "covered_lines" => 0,
                                  "lines_covered_percent" => 0.0, "lines" => [0, 0]
                                }
                              }
                            ))

      expect(run("uncovered", "--input", json_path, "--annotate", "github")).to eq(0)
      expect(stdout.string).to eq("::warning file=lib/b.rb,line=1,endLine=2::Not covered by tests\n")
    end

    it "names itself and the criterion it does not know" do
      expect(run("uncovered", "--input", json_path, "--criterion", "nope")).to eq(1)
      expect(stderr.string)
        .to eq("simplecov uncovered: unknown --criterion :nope (expected line, branch, or method)\n")
    end

    it "names itself and the input it cannot find" do
      missing = File.join(tmp, "nope.json")

      expect(run("uncovered", "--input", missing)).to eq(1)
      expect(stderr.string).to eq("simplecov uncovered: #{missing} not found\n")
    end

    it "honours --threshold" do
      run("uncovered", "--input", json_path, "--threshold", "20")
      expect(stdout.string.lines.map(&:strip)).to all(include("/abs/lib/c.rb"))
    end

    it "honours --top to cap the list" do
      run("uncovered", "--input", json_path, "--top", "1")
      expect(stdout.string.lines.size).to eq(1)
    end

    it "rejects a negative --top instead of raising" do
      expect(run("uncovered", "--input", json_path, "--top", "-1")).to eq(1)
      expect(stderr.string).to include("invalid argument: --top must not be negative")
      expect(stdout.string).to be_empty
    end

    it "reports nothing when every file is at 100%" do
      File.write(json_path, JSON.dump(
                              "coverage" => {
                                "/abs/lib/a.rb" => {
                                  "total_lines" => 10, "covered_lines" => 10, "lines_covered_percent" => 100.0
                                }
                              }
                            ))
      run("uncovered", "--input", json_path)
      expect(stdout.string).to include("nothing to report")
    end

    it "emits rows as a JSON array under --json" do
      expect(run("uncovered", "--input", json_path, "--json")).to eq(0)
      payload = JSON.parse(stdout.string)
      expect(payload).to be_an(Array)
      expect(payload.first).to include("file" => "/abs/lib/c.rb", "percent" => 10.0, "covered" => 1, "total" => 10)
      expect(payload.last).to include("file" => "/abs/lib/b.rb", "percent" => 50.0, "covered" => 5, "total" => 10)
    end

    it "emits an empty JSON array when nothing is uncovered" do
      File.write(json_path, JSON.dump(
                              "coverage" => {
                                "/abs/lib/a.rb" => {
                                  "total_lines" => 10, "covered_lines" => 10, "lines_covered_percent" => 100.0
                                }
                              }
                            ))
      expect(run("uncovered", "--input", json_path, "--json")).to eq(0)
      expect(JSON.parse(stdout.string)).to eq([])
    end

    it "ranks by the chosen --criterion" do
      File.write(json_path, JSON.dump(
                              "coverage" => {
                                "/abs/lib/a.rb" => {
                                  "total_lines" => 10, "covered_lines" => 10, "lines_covered_percent" => 100.0,
                                  "total_branches" => 4, "covered_branches" => 1, "branches_covered_percent" => 25.0
                                }
                              }
                            ))
      expect(run("uncovered", "--input", json_path, "--criterion", "branch")).to eq(0)
      expect(stdout.string).to include("/abs/lib/a.rb").and include("25.00%")
    end

    it "rejects an unknown --criterion" do
      expect(run("uncovered", "--input", json_path, "--criterion", "bogus")).to eq(1)
      expect(stderr.string).to include("unknown --criterion")
    end

    context "with colorization" do
      it "colorizes the listed percentages when Color.enabled? is true" do
        allow(SimpleCov::Color).to receive(:enabled?).and_return(true)
        expect(run("uncovered", "--input", json_path)).to eq(0)
        # Both listed files are below the yellow threshold so both render red
        expect(stdout.string).to match(/\e\[31m\s+10\.00%\e\[0m/)
        expect(stdout.string).to match(/\e\[31m\s+50\.00%\e\[0m/)
      end

      it_behaves_like "a --no-color subcommand" do
        let(:no_color_argv) { ["uncovered", "--input", json_path, "--no-color"] }
      end
    end

    it "skips coverage entries without a positive total_lines count" do
      File.write(json_path, JSON.dump(
                              "coverage" => {
                                "/abs/lib/empty.rb" => {"total_lines" => 0},
                                "/abs/lib/a.rb" => {
                                  "total_lines" => 10, "covered_lines" => 5, "lines_covered_percent" => 50.0
                                }
                              }
                            ))
      run("uncovered", "--input", json_path)
      expect(stdout.string).not_to include("empty.rb")
      expect(stdout.string).to include("a.rb")
    end

    it "errors when the input file is missing" do
      expect(run("uncovered", "--input", "/no/such.json")).to eq(1)
      expect(stderr.string).to include("not found")
    end
  end

  describe "merge subcommand", mutant_expression: "SimpleCov::CLI::Merge*" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-merge-spec-") }
    let(:a) { File.join(tmp, "a.json") }
    let(:b) { File.join(tmp, "b.json") }
    let(:out) { File.join(tmp, "merged.json") }
    # Use a real on-disk file inside SimpleCov.root so the default
    # root_filter doesn't strip it during result construction.
    let(:file) { File.expand_path("spec/fixtures/sample.rb", SimpleCov.root) }
    let(:c) { File.join(tmp, "c.json") }

    after { FileUtils.remove_entry(tmp) }

    def write_resultset(path, command_name, file_path, lines, outdated: false)
      File.write(path, JSON.dump(
                         command_name => {
                           "coverage" => {file_path => {"lines" => lines}},
                           "timestamp" => outdated ? Time.now.to_i - 100_000 : Time.now.to_i
                         }
                       ))
    end

    it "loads the full library on the way to the merger it hands back" do
      allow(SimpleCov::CLI::Merge).to receive(:require)

      expect(SimpleCov::CLI::Merge.send(:result_merger)).to be(SimpleCov::ResultMerger)
      expect(SimpleCov::CLI::Merge).to have_received(:require).with("simplecov")
    end

    # Nothing said to honour it, so a stale resultset is still merged.
    it "ignores the merge timeout unless told to honour it" do
      write_resultset(a, "worker_1", file, [1, 0, nil], outdated: true)

      expect(run("merge", "--output", out, a)).to eq(0)
      expect(JSON.parse(File.read(out)).keys).to eq(["worker_1"])
    end

    it "quotes what the JSON parser said about an unparseable input" do
      File.write(a, "{")

      expect(run("merge", "--output", out, a)).to eq(1)
      expect(stderr.string).to match(/\Asimplecov merge: input file .* isn't valid JSON \(.+\)\n\z/)
      expect(stderr.string).not_to include("()")
    end

    # The first command name belongs to one file only. Skipping it must
    # not stop the sweep before the duplicate that follows.
    it "warns about a duplicate that follows a command name of its own" do
      write_resultset(a, "solo", file, [1, 0, nil])
      write_resultset(b, "shared", file, [0, 1, nil])
      write_resultset(c, "shared", file, [1, 1, nil])

      expect(run("merge", "--output", out, a, b, c)).to eq(0)
      expect(stderr.string).to include(%(command_name "shared" appears in 2 input files))
    end

    # The require is lazy, so the read-only subcommands never pay for
    # ResultMerger. A process that already has simplecov loaded cannot
    # tell whether it happened, so this asks one that does not.
    it "loads the library it merges with, in a process that has not" do
      write_resultset(a, "worker_1", file, [1, 0, nil])
      exe = File.expand_path("../exe/simplecov", __dir__)
      lib = File.expand_path("../lib", __dir__)

      stdout_text, stderr_text, status =
        Open3.capture3(RbConfig.ruby, "-I", lib, exe, "merge", "--output", out, a)

      expect(status.exitstatus).to eq(0), stderr_text
      expect(stdout_text).to include("wrote #{out}")
    end

    it "stops at missing input files rather than going on" do
      expect(run("merge", "--output", out)).to eq(1)
      expect(stderr.string).to eq("simplecov merge: missing input files\n")
      expect(File.exist?(out)).to be false
    end

    it "errors when no input files are given" do
      expect(run("merge")).to eq(1)
      expect(stderr.string).to include("missing input files")
    end

    it "merges two resultsets and writes the merged JSON to --output" do
      write_resultset(a, "worker_1", file, [1, 0, nil])
      write_resultset(b, "worker_2", file, [1, 1, nil])

      expect(run("merge", "--output", out, a, b)).to eq(0)
      merged = JSON.parse(File.read(out))
      expect(merged.keys.first).to include("worker_1")
      expect(merged.keys.first).to include("worker_2")
      expect(merged.values.first.dig("coverage", file, "lines")).to eq([2, 1, nil])
    end

    it "surfaces a specific JSON parse error for an unparseable input" do
      bad = File.join(tmp, "bad.json")
      File.write(bad, "")
      expect(run("merge", "--output", out, bad)).to eq(1)
      expect(stderr.string).to include("isn't valid JSON")
      expect(stderr.string).to include("bad.json")
    end

    it "surfaces a specific error when an input is structurally empty" do
      empty = File.join(tmp, "empty.json")
      File.write(empty, "{}")
      expect(run("merge", "--output", out, empty)).to eq(1)
      expect(stderr.string).to include("no resultset entries")
      expect(stderr.string).to include("empty.json")
    end

    it "surfaces a specific error when an input file doesn't exist" do
      expect(run("merge", "--output", out, File.join(tmp, "nope.json"))).to eq(1)
      expect(stderr.string).to include("not found")
      expect(stderr.string).to include("nope.json")
    end

    # A directory passed File.exist? and then File.read raised EISDIR
    # with a full backtrace; EACCES behaved the same. The read errors
    # must come back as the same one-line reports the other input
    # problems get.
    it "surfaces a specific error when an input path is not a readable file" do
      expect(run("merge", "--output", out, tmp)).to eq(1)
      expect(stderr.string).to match(/\Asimplecov merge: input file "\S.*" cannot be read \(\S.*\)\n\z/)
    end

    # git and the kernel sometimes answer with more than one line. The
    # status line takes the first of them, without its newline, so the
    # report stays one complaint per file.
    it "reports only the first line of a multi-line read error" do
      wordy = Errno::EACCES.new("first line\nsecond line")
      allow(File).to receive(:read).and_raise(wordy)

      expect(run("merge", "--output", out, a)).to eq(1)
      expect(stderr.string.lines.size).to eq(1)
      expect(stderr.string).to end_with("cannot be read (#{wordy.message.lines.first.rstrip})\n")
    end

    it "reports an unreadable input whose error says nothing" do
      silent = Class.new(Errno::EACCES) { def message = "" }
      allow(File).to receive(:read).and_raise(silent.new)

      expect(run("merge", "--output", out, a)).to eq(1)
      expect(stderr.string).to end_with("cannot be read ()\n")
    end

    it "errors when --honor-timeout expires every input's entries" do
      # Far enough in the past that any reasonable merge_timeout drops it.
      File.write(a, JSON.dump("worker_1" => {"coverage" => {file => {"lines" => [1]}},
                                             "timestamp" => Time.now.to_i - 86_400}))
      expect(run("merge", "--output", out, "--honor-timeout", a)).to eq(1)
      expect(stderr.string).to include("no mergeable results")
    end

    it "warns when two input files share a command_name" do
      write_resultset(a, "RSpec", file, [1, 0, nil])
      write_resultset(b, "RSpec", file, [0, 1, nil])

      expect(run("merge", "--output", out, a, b)).to eq(0)
      expect(stderr.string).to eq(
        %(simplecov merge: warning \u2014 command_name "RSpec" appears in 2 input files ) \
        "(#{a}, #{b}); entries will be merged\n"
      )
    end

    it "writes to the project resultset when no output is named" do
      write_resultset(a, "worker_1", file, [1, 0, nil])
      allow(described_class).to receive(:default_resultset).and_return(out)

      expect(run("merge", a)).to eq(0)
      expect(stdout.string).to eq("simplecov merge: wrote #{out}\n")
    end

    # One command name in one file is not a duplicate.
    it "stays quiet when the command names are distinct" do
      write_resultset(a, "worker_1", file, [1, 0, nil])
      write_resultset(b, "worker_2", file, [1, 1, nil])

      expect(run("merge", "--output", out, a, b)).to eq(0)
      expect(stderr.string).to be_empty
    end

    it "says it wrote the output when it did" do
      write_resultset(a, "worker_1", file, [1, 0, nil])

      expect(run("merge", "--output", out, a)).to eq(0)
      expect(stdout.string).to eq("simplecov merge: wrote #{out}\n")
    end

    # A resultset is an object of command names. A JSON array parses,
    # and is not one.
    it "surfaces a specific error when an input is not an object" do
      File.write(a, JSON.dump([{"coverage" => {}}]))

      expect(run("merge", "--output", out, a)).to eq(1)
      expect(stderr.string).to eq(%(simplecov merge: input file #{a.inspect} has no resultset entries\n))
    end

    it "doesn't write the output file under --dry-run" do
      write_resultset(a, "worker_1", file, [1, 0, nil])

      expect(run("merge", "--output", out, "--dry-run", a)).to eq(0)
      expect(File.exist?(out)).to be false
      expect(stdout.string).to eq("simplecov merge: would write #{out}\n")
    end

    it "silences the success status line under --quiet" do
      write_resultset(a, "worker_1", file, [1, 0, nil])

      expect(run("merge", "--output", out, "--quiet", a)).to eq(0)
      expect(stdout.string).to be_empty
      expect(File.exist?(out)).to be true
    end

    it "accepts -q as the short alias for --quiet" do
      write_resultset(a, "worker_1", file, [1, 0, nil])

      expect(run("merge", "--output", out, "-q", a)).to eq(0)
      expect(stdout.string).to be_empty
    end
  end

  describe "diff subcommand", mutant_expression: "SimpleCov::CLI::Diff*" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-diff-spec-") }
    let(:current) { File.join(tmp, "current.json") }
    let(:baseline) { File.join(tmp, "baseline.json") }

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

    it "lists per-file deltas, regressions first" do
      write_coverage(baseline, "lib/a.rb" => 80, "lib/b.rb" => 50, "lib/c.rb" => 100)
      write_coverage(current,  "lib/a.rb" => 85, "lib/b.rb" => 30, "lib/c.rb" => 100)

      expect(run("diff", "--input", current, baseline)).to eq(0)
      lines = stdout.string.lines.map(&:strip)
      expect(lines.size).to eq(2)
      expect(lines.first).to include("lib/b.rb")
      expect(lines.first).to match(/-\s*20\.00%/)
      expect(lines.last).to include("lib/a.rb")
      expect(lines.last).to match(/\+\s*5\.00%/)
    end

    it "treats new files as a 0%-baseline delta" do
      write_coverage(baseline, "lib/a.rb" => 80)
      write_coverage(current,  "lib/a.rb" => 80, "lib/new.rb" => 60)

      run("diff", "--input", current, baseline)
      expect(stdout.string).to include("lib/new.rb")
      expect(stdout.string).to match(/\+\s*60\.00%/)
    end

    it "exits 0 with a friendly message when nothing moved" do
      write_coverage(baseline, "lib/a.rb" => 80)
      write_coverage(current,  "lib/a.rb" => 80)

      expect(run("diff", "--input", current, baseline)).to eq(0)
      expect(stdout.string).to include("no per-file coverage changes")
    end

    it "exits non-zero on regression when --fail-on-drop is set" do
      write_coverage(baseline, "lib/a.rb" => 80)
      write_coverage(current,  "lib/a.rb" => 70)

      expect(run("diff", "--input", current, "--fail-on-drop", baseline)).to eq(1)
    end

    # Row inclusion and display both treat sub-EPSILON deltas as float
    # noise, so the gate must too: a row listed for a gain in one
    # criterion used to exit 1 over a 1e-14 drift in another, failing CI
    # with only gains visible in the output.
    it "does not fail on sub-epsilon float noise under --fail-on-drop" do
      write_coverage(baseline,
                     "lib/a.rb" => {"covered_lines" => 80, "lines_covered_percent" => 80.0,
                                    "total_branches" => 20, "covered_branches" => 16,
                                    "branches_covered_percent" => 80.0})
      write_coverage(current,
                     "lib/a.rb" => {"covered_lines" => 85, "lines_covered_percent" => 85.0,
                                    "total_branches" => 20, "covered_branches" => 16,
                                    "branches_covered_percent" => 80.0 - 1e-14})

      expect(run("diff", "--input", current, "--fail-on-drop", baseline)).to eq(0)
      expect(stdout.string).to include("lib/a.rb")
      expect(stdout.string).to match(/\+\s*5\.00%\s+lines/)
    end

    it "errors when the baseline argument is missing" do
      expect(run("diff")).to eq(1)
      expect(stderr.string).to include("missing baseline argument")
    end

    # The threshold is a distance, so the sign the user typed says
    # nothing: --threshold -5 asks for the same files --threshold 5 does.
    # Read without the abs, a negative floor admits every row, since any
    # delta at all is greater than a negative number.
    it "reads a negative threshold as the same distance as a positive one" do
      write_coverage(baseline, "lib/small.rb" => 80, "lib/big.rb" => 50)
      write_coverage(current,  "lib/small.rb" => 83, "lib/big.rb" => 56)

      expect(run("diff", "--input", current, "--threshold", "-5", baseline)).to eq(0)
      expect(stdout.string).to include("lib/big.rb")
      expect(stdout.string).not_to include("lib/small.rb")
    end

    # A file Coverage measured no lines of reports 100%, which is not a
    # coverage level so much as the absence of one. Counted as 100 it
    # cancels against a real 100 and the file vanishes from the diff.
    it "reads a file with nothing to cover as 0%, not as fully covered" do
      write_coverage(baseline, "lib/a.rb" => {"total_lines" => 0, "covered_lines" => 0,
                                              "lines_covered_percent" => 100.0})
      write_coverage(current,  "lib/a.rb" => {"total_lines" => 100, "covered_lines" => 100,
                                              "lines_covered_percent" => 100.0})

      expect(run("diff", "--input", current, baseline)).to eq(0)
      expect(stdout.string).to include("lib/a.rb")
      expect(stdout.string).to match(/\+\s*100\.00%/)
    end

    # `include` cannot see a part that is missing, an extra separator, or
    # a nil rendered into the join, so the whole line is pinned.
    it "renders a row as sign, width-aligned delta, criterion and file" do
      write_coverage(baseline, "lib/a.rb" => 80)
      write_coverage(current,  "lib/a.rb" => 85)

      run("diff", "--input", current, baseline)
      expect(stdout.string).to eq("  +  5.00% lines  lib/a.rb\n")
    end

    it "renders every criterion that moved, and only those" do
      write_coverage(baseline,
                     "lib/a.rb" => {"covered_lines" => 80, "lines_covered_percent" => 80.0,
                                    "total_branches" => 10, "covered_branches" => 5,
                                    "branches_covered_percent" => 50.0,
                                    "total_methods" => 10, "covered_methods" => 4,
                                    "methods_covered_percent" => 40.0})
      write_coverage(current,
                     "lib/a.rb" => {"covered_lines" => 80, "lines_covered_percent" => 80.0,
                                    "total_branches" => 10, "covered_branches" => 7,
                                    "branches_covered_percent" => 70.0,
                                    "total_methods" => 10, "covered_methods" => 3,
                                    "methods_covered_percent" => 30.0})

      run("diff", "--input", current, baseline)
      expect(stdout.string).to eq("    0.00% lines  + 20.00% branches  -10.00% methods  lib/a.rb\n")
    end

    it "marks an added file and a removed one by name" do
      write_coverage(baseline, "lib/gone.rb" => 80)
      write_coverage(current,  "lib/new.rb" => 60)

      run("diff", "--input", current, baseline)
      expect(stdout.string.lines.map(&:chomp)).to contain_exactly(
        "  -80.00% lines  lib/gone.rb  (removed)",
        "  + 60.00% lines  lib/new.rb  (new file)"
      )
    end

    # The default floor is zero, not one: a move smaller than a full
    # percent is still a move, and only EPSILON-scale noise is dropped.
    it "lists a sub-one-percent move under the default threshold" do
      write_coverage(baseline, "lib/a.rb" => {"covered_lines" => 80, "lines_covered_percent" => 80.0})
      write_coverage(current,  "lib/a.rb" => {"covered_lines" => 80, "lines_covered_percent" => 80.5})

      run("diff", "--input", current, baseline)
      expect(stdout.string).to include("lib/a.rb")
    end

    # A payload that is not an object has no fields to read, and asking
    # an Array for a string key raises rather than answering nil.
    it "reads a non-object payload as 0%, whatever it is" do
      File.write(current, JSON.dump("coverage" => {"lib/a.rb" => [1, 2, 3]}))
      write_coverage(baseline, "lib/a.rb" => 80)

      expect(run("diff", "--input", current, baseline)).to eq(0)
      expect(stdout.string).to include("lib/a.rb").and include("-80.00%")
    end

    # Two positional arguments, so the one that is read is identified by
    # position rather than by being the only one there.
    it "reads the baseline from the first positional argument" do
      other = File.join(tmp, "other.json")
      write_coverage(baseline, "lib/a.rb" => 80)
      write_coverage(other,    "lib/a.rb" => 10)
      write_coverage(current,  "lib/a.rb" => 85)

      run("diff", "--input", current, baseline, other)
      expect(stdout.string).to include("+  5.00%")
    end

    # coverage.json is JSON someone else may have written, so a percent
    # can arrive as a string. Read without the coercion it reaches the
    # subtraction as one and raises.
    it "coerces a percent that arrived as a string" do
      File.write(baseline, JSON.dump("coverage" => {"lib/a.rb" => {
                                       "total_lines" => 100, "covered_lines" => 80,
                                       "lines_covered_percent" => "80.0"
                                     }}))
      write_coverage(current, "lib/a.rb" => 85)

      expect(run("diff", "--input", current, baseline)).to eq(0)
      expect(stdout.string).to include("+  5.00%")
    end

    it "colorizes every criterion it prints, not only the first" do
      allow(SimpleCov::Color).to receive(:enabled?).and_return(true)
      write_coverage(baseline,
                     "lib/a.rb" => {"covered_lines" => 80, "lines_covered_percent" => 80.0,
                                    "total_branches" => 10, "covered_branches" => 5,
                                    "branches_covered_percent" => 50.0,
                                    "total_methods" => 10, "covered_methods" => 4,
                                    "methods_covered_percent" => 40.0})
      write_coverage(current,
                     "lib/a.rb" => {"covered_lines" => 85, "lines_covered_percent" => 85.0,
                                    "total_branches" => 10, "covered_branches" => 7,
                                    "branches_covered_percent" => 70.0,
                                    "total_methods" => 10, "covered_methods" => 3,
                                    "methods_covered_percent" => 30.0})

      run("diff", "--input", current, baseline)
      expect(stdout.string).to include("\e[32m+  5.00% lines\e[0m")
        .and include("\e[32m+ 20.00% branches\e[0m")
        .and include("\e[31m-10.00% methods\e[0m")
    end

    # A payload can count lines without carrying the percent alongside
    # them, and a missing percent is a file to read as uncovered rather
    # than an input to abort on.
    it "reads a payload that counts lines but omits the percent as 0%" do
      File.write(baseline, JSON.dump("coverage" => {"lib/a.rb" => {"total_lines" => 100,
                                                                   "covered_lines" => 80}}))
      write_coverage(current, "lib/a.rb" => 85)

      expect(run("diff", "--input", current, baseline)).to eq(0)
      expect(stdout.string).to include("+ 85.00%")
    end

    it "names the subcommand in the error when the baseline cannot be read" do
      write_coverage(current, "lib/a.rb" => 80)

      run("diff", "--input", current, baseline)
      expect(stderr.string).to start_with("simplecov diff:")
    end

    it "errors when the baseline file is missing" do
      write_coverage(current, "lib/a.rb" => 80)

      expect(run("diff", "--input", current, baseline)).to eq(1)
      expect(stderr.string).to include(baseline).and include("not found")
    end

    it "errors when the current input file is missing" do
      write_coverage(baseline, "lib/a.rb" => 80)

      expect(run("diff", "--input", current, baseline)).to eq(1)
      expect(stderr.string).to include(current).and include("not found")
    end

    it "fails on a branch coverage drop when --fail-on-drop is set" do
      write_coverage(baseline,
                     "lib/a.rb" => {"covered_lines" => 80, "lines_covered_percent" => 80.0,
                                    "total_branches" => 20, "covered_branches" => 16,
                                    "branches_covered_percent" => 80.0})
      write_coverage(current,
                     "lib/a.rb" => {"covered_lines" => 80, "lines_covered_percent" => 80.0,
                                    "total_branches" => 20, "covered_branches" => 10,
                                    "branches_covered_percent" => 50.0})

      expect(run("diff", "--input", current, "--fail-on-drop", baseline)).to eq(1)
      expect(stdout.string).to include("lib/a.rb")
      expect(stdout.string).to match(/-\s*30\.00%\s+branches/)
    end

    it "fails on a method coverage drop when --fail-on-drop is set" do
      write_coverage(baseline,
                     "lib/a.rb" => {"covered_lines" => 80, "lines_covered_percent" => 80.0,
                                    "total_methods" => 20, "covered_methods" => 18,
                                    "methods_covered_percent" => 90.0})
      write_coverage(current,
                     "lib/a.rb" => {"covered_lines" => 80, "lines_covered_percent" => 80.0,
                                    "total_methods" => 20, "covered_methods" => 15,
                                    "methods_covered_percent" => 75.0})

      expect(run("diff", "--input", current, "--fail-on-drop", baseline)).to eq(1)
      expect(stdout.string).to include("lib/a.rb")
      expect(stdout.string).to match(/-\s*15\.00%\s+methods/)
    end

    it "tags new files with (new file) and removed files with (removed)" do
      write_coverage(baseline, "lib/gone.rb" => 95)
      write_coverage(current,  "lib/new.rb"  => 60)

      expect(run("diff", "--input", current, baseline)).to eq(0)
      expect(stdout.string).to include("lib/new.rb")
      expect(stdout.string).to include("(new file)")
      expect(stdout.string).to include("lib/gone.rb")
      expect(stdout.string).to include("(removed)")
    end

    it "normalizes leading slashes so pre-`project_filename` baselines diff cleanly" do
      write_coverage(baseline, "/lib/foo.rb" => 80)
      write_coverage(current,  "lib/foo.rb" => 80)

      expect(run("diff", "--input", current, baseline)).to eq(0)
      expect(stdout.string).to include("no per-file coverage changes")
    end

    it "emits a JSON array under --json" do
      write_coverage(baseline, "lib/a.rb" => 80)
      write_coverage(current,  "lib/a.rb" => 70)

      expect(run("diff", "--input", current, "--json", baseline)).to eq(0)
      payload = JSON.parse(stdout.string)
      expect(payload).to be_an(Array)
      expect(payload.first).to include("file" => "lib/a.rb", "status" => "changed", "line_delta" => -10.0)
    end

    it "honors --threshold to filter out small-delta noise" do
      write_coverage(baseline, "lib/a.rb" => 80, "lib/b.rb" => 80)
      write_coverage(current,  "lib/a.rb" => 75, "lib/b.rb" => 60)

      run("diff", "--input", current, "--threshold", "10", baseline)
      expect(stdout.string).to include("lib/b.rb")
      expect(stdout.string).not_to include("lib/a.rb")
    end

    it "includes a file whose delta is exactly the threshold" do
      write_coverage(baseline, "lib/a.rb" => 80)
      write_coverage(current,  "lib/a.rb" => 70)

      run("diff", "--input", current, "--threshold", "10", baseline)
      expect(stdout.string).to include("lib/a.rb")
    end

    it "does not fail on a deleted file under --fail-on-drop" do
      write_coverage(baseline, "lib/a.rb" => 80, "lib/gone.rb" => 100)
      write_coverage(current,  "lib/a.rb" => 80)

      expect(run("diff", "--input", current, "--fail-on-drop", baseline)).to eq(0)
      expect(stdout.string).to include("(removed)")
    end

    context "with colorization" do
      it "colorizes regressions red and improvements green when Color.enabled? is true" do
        allow(SimpleCov::Color).to receive(:enabled?).and_return(true)
        write_coverage(baseline, "lib/a.rb" => 80, "lib/b.rb" => 50)
        write_coverage(current,  "lib/a.rb" => 85, "lib/b.rb" => 30)

        expect(run("diff", "--input", current, baseline)).to eq(0)
        expect(stdout.string).to match(/\e\[31m-\s*20\.00% lines\e\[0m/)
        expect(stdout.string).to match(/\e\[32m\+\s*5\.00% lines\e\[0m/)
      end

      it_behaves_like "a --no-color subcommand" do
        before do
          write_coverage(baseline, "lib/a.rb" => 80)
          write_coverage(current,  "lib/a.rb" => 70)
        end

        let(:no_color_argv) { ["diff", "--input", current, "--no-color", baseline] }
      end
    end
  end

  describe "ratchet subcommand", mutant_expression: "SimpleCov::CLI::Ratchet*" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-ratchet-spec-") }
    let(:input) { File.join(tmp, "coverage.json") }
    let(:baseline_path) { File.join(tmp, ".simplecov_baseline.yml") }

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
      SimpleCov::Baseline.read(baseline_path)
    end

    it "loads the full library before touching Baseline and the dotfile default" do
      allow(SimpleCov::CLI::Ratchet).to receive(:require)
      write_report("lib/foo.rb" => {percent: 41.2, missed: 137})

      run("ratchet", "--input", input, "--baseline", baseline_path, "--dry-run", "--quiet")

      expect(SimpleCov::CLI::Ratchet).to have_received(:require).with("simplecov")
    end

    # The whole payload: every fact the JSON view carries, under the key
    # it carries it, so a key that went missing or was renamed shows.
    it "reports a generated pass as JSON" do
      write_report("lib/foo.rb" => {percent: 41.2, missed: 137})

      expect(run("ratchet", "--input", input, "--baseline", baseline_path, "--json")).to eq(0)
      expect(JSON.parse(stdout.string)).to eq(
        "written" => true, "path" => baseline_path, "generated" => true, "files" => 1,
        "tightened" => [], "pruned" => [], "regressed" => [], "unchanged" => []
      )
    end

    it "says nothing was written under --dry-run" do
      write_report("lib/foo.rb" => {percent: 41.2, missed: 137})

      run("ratchet", "--input", input, "--baseline", baseline_path, "--json", "--dry-run")
      expect(JSON.parse(stdout.string)).to include("written" => false)
      expect(File).not_to exist(baseline_path)
    end

    it "reports a ratcheted pass as JSON, saying it generated nothing" do
      write_report("lib/foo.rb" => {percent: 41.2, missed: 137})
      run("ratchet", "--input", input, "--baseline", baseline_path)
      stdout.truncate(stdout.rewind)

      run("ratchet", "--input", input, "--baseline", baseline_path, "--json")
      expect(JSON.parse(stdout.string)).to include("generated" => false, "files" => 1)
    end

    it "names itself when the report cannot be read" do
      expect(run("ratchet", "--input", File.join(tmp, "absent.json"), "--baseline", baseline_path)).to eq(1)
      expect(stderr.string).to eq("simplecov ratchet: #{File.join(tmp, 'absent.json')} not found\n")
    end

    it "reports a baseline it cannot make sense of" do
      write_report("lib/foo.rb" => {percent: 41.2, missed: 137})
      File.write(baseline_path, "not: [a, baseline\n")

      expect(run("ratchet", "--input", input, "--baseline", baseline_path)).to eq(1)
      expect(stderr.string).to start_with("simplecov ratchet:")
    end

    describe "which rows can become a floor" do
      # A row from another tool may carry one half of the pair; a floor
      # needs both, and needs them as numbers.
      it "takes a row that carries both a percent and a count" do
        expect(described_class::Ratchet.usable?(41.2, 137)).to be(true)
      end

      it "refuses a row whose percent is not a number" do
        expect(described_class::Ratchet.usable?("41.2", 137)).to be(false)
      end

      it "refuses a row with no count beside the percent" do
        expect(described_class::Ratchet.usable?(41.2, nil)).to be(false)
      end

      # A count is whole: a fractional one is not a number of lines.
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

      # A ratcheted pass counts what moved rather than what exists.
      it "counts what moved once a baseline is there" do
        run("ratchet", "--input", input, "--baseline", baseline_path)
        stdout.truncate(stdout.rewind)
        write_report("lib/foo.rb" => {percent: 80.0, missed: 2})

        run("ratchet", "--input", input, "--baseline", baseline_path)
        expect(stdout.string).to eq(
          "simplecov ratchet: wrote #{baseline_path} (1 tightened, 0 pruned, 0 unchanged)\n"
        )
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

    # A percent from a report carries whatever precision the writer used;
    # a floor is stored at the precision SimpleCov rounds to.
    it "rounds a floor to the precision coverage is reported at" do
      write_report("lib/foo.rb" => {percent: 41.23456789, missed: 137})

      run("ratchet", "--input", input, "--baseline", baseline_path)
      expect(read_baseline.entries.fetch("lib/foo.rb").fetch(:line).percent)
        .to eq(SimpleCov.round_coverage(41.23456789))
    end

    it "refuses a stray positional argument, naming the first" do
      write_report("lib/foo.rb" => {percent: 41.2, missed: 137})

      expect(run("ratchet", "--input", input, "--baseline", baseline_path, "stray", "another")).to eq(1)
      expect(stderr.string).to eq("simplecov ratchet: unexpected argument \"stray\"\n")
    end

    it "generates a full baseline when none exists" do
      write_report(
        "lib/foo.rb" => {percent: 41.2, missed: 137, branch_percent: 25.0, branch_missed: 3},
        "lib/bar.rb" => {percent: 100.0, missed: 0}
      )

      expect(run("ratchet", "--input", input, "--baseline", baseline_path)).to eq(0)
      expect(stdout.string).to include("wrote #{baseline_path}")
      expect(stdout.string).to include("2 files")

      baseline = read_baseline
      expect(baseline.floor_for("lib/foo.rb", :line)).to have_attributes(percent: 41.2, missed: 137)
      expect(baseline.floor_for("lib/foo.rb", :branch)).to have_attributes(percent: 25.0, missed: 3)
      expect(baseline.floor_for("lib/bar.rb", :line)).to have_attributes(percent: 100.0, missed: 0)
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

      it "tightens improved floors, keeps regressed ones, prunes deleted files, adds nothing" do
        expect(run("ratchet", "--input", input, "--baseline", baseline_path)).to eq(0)

        baseline = read_baseline
        expect(baseline.floor_for("lib/improved.rb", :line)).to have_attributes(percent: 75.0, missed: 4)
        expect(baseline.floor_for("lib/regressed.rb", :line)).to have_attributes(percent: 90.0, missed: 2)
        expect(baseline.entry_for("lib/deleted.rb")).to be_nil
        expect(baseline.entry_for("lib/brand_new.rb")).to be_nil
      end

      it "summarizes what moved, including the files still below their floors" do
        run("ratchet", "--input", input, "--baseline", baseline_path)

        expect(stdout.string).to include("1 tightened, 1 pruned, 0 unchanged")
        expect(stdout.string).to include("1 file below its floor")
      end

      it "prints without writing under --dry-run" do
        before_content = File.read(baseline_path)
        expect(run("ratchet", "--input", input, "--baseline", baseline_path, "--dry-run")).to eq(0)

        expect(stdout.string).to include("would write")
        expect(File.read(baseline_path)).to eq(before_content)
      end

      it "regenerates from scratch under --init, adding new files and resetting floors" do
        expect(run("ratchet", "--input", input, "--baseline", baseline_path, "--init")).to eq(0)

        baseline = read_baseline
        expect(baseline.entry_for("lib/brand_new.rb")).not_to be_nil
        expect(baseline.entry_for("lib/deleted.rb")).to be_nil
        # --init is the escape hatch: floors reset to the current state,
        # regression included.
        expect(baseline.floor_for("lib/regressed.rb", :line)).to have_attributes(percent: 80.0, missed: 6)
      end

      it "emits the summary as JSON under --json" do
        expect(run("ratchet", "--input", input, "--baseline", baseline_path, "--json")).to eq(0)

        expect(JSON.parse(stdout.string)).to include(
          "written" => true, "path" => baseline_path,
          "tightened" => ["lib/improved.rb"], "pruned" => ["lib/deleted.rb"],
          "regressed" => ["lib/regressed.rb"], "unchanged" => []
        )
      end
    end

    # A report written by another tool can carry rows without the missed
    # counts; only a complete percent-and-missed pair can become a floor.
    it "skips report rows without usable counts" do
      File.write(input, JSON.dump("coverage" => {
                                    "lib/counted.rb" => {"lines_covered_percent" => 80.0, "covered_lines" => 8,
                                                         "missed_lines" => 2, "total_lines" => 10},
                                    "lib/percent_only.rb" => {"lines_covered_percent" => 50.0}
                                  }))

      expect(run("ratchet", "--input", input, "--baseline", baseline_path)).to eq(0)

      baseline = read_baseline
      expect(baseline.entry_for("lib/counted.rb")).not_to be_nil
      expect(baseline.entry_for("lib/percent_only.rb")).to be_nil
    end

    it "pluralizes the below-floor note" do
      File.write(baseline_path, <<~YAML)
        lib/one.rb:
          lines:
            percent: 90.0
            missed: 0
        lib/two.rb:
          lines:
            percent: 90.0
            missed: 0
      YAML
      write_report(
        "lib/one.rb" => {percent: 50.0, missed: 5},
        "lib/two.rb" => {percent: 50.0, missed: 5}
      )

      run("ratchet", "--input", input, "--baseline", baseline_path)

      expect(stdout.string).to include("2 files below their floors")
    end

    it "rejects a stray positional argument" do
      expect(run("ratchet", "stray")).to eq(1)
      expect(stderr.string).to include('unexpected argument "stray"')
    end

    it "errors on a malformed baseline file" do
      write_report("lib/foo.rb" => {percent: 41.2, missed: 137})
      File.write(baseline_path, "{")

      expect(run("ratchet", "--input", input, "--baseline", baseline_path)).to eq(1)
      expect(stderr.string).to start_with("simplecov ratchet:")
      expect(stderr.string).to include("not valid YAML")
    end

    it "defaults the baseline path to .simplecov_baseline.yml in the working directory" do
      write_report("lib/foo.rb" => {percent: 41.2, missed: 137})

      Dir.chdir(tmp) { expect(run("ratchet", "--input", input)).to eq(0) }
      expect(File).to exist(baseline_path)
    end

    it "honors SimpleCov.baseline_file from a project .simplecov" do
      write_report("lib/foo.rb" => {percent: 41.2, missed: 137})
      File.write(File.join(tmp, ".simplecov"), %(SimpleCov.baseline_file "floors.yml"\n))

      Dir.chdir(tmp) { expect(run("ratchet", "--input", input)).to eq(0) }
      expect(File).to exist(File.join(tmp, "floors.yml"))
      expect(File).not_to exist(baseline_path)
    end
  end

  # The history renderer, driven directly. The subcommand's own examples
  # write a history file and run the command; these pin the table it
  # draws, which is where nearly all of this code lives.
  describe "history output", mutant_expression: "SimpleCov::CLI::History*" do
    let(:renderer) { SimpleCov::CLI::History::Output }
    let(:out) { StringIO.new }
    let(:entries) do
      [{"created_at" => "2026-08-01T00:00:00Z", "branch" => "main", "commit" => "abcdef1234",
        "totals" => {"line" => 90.0, "branch" => 80.0}, "files" => {"lib/a.rb" => {"line" => 50.0}}},
       {"created_at" => "2026-08-02T00:00:00Z", "branch" => "feature-x", "commit" => "1234567890",
        "totals" => {"line" => 95.0, "branch" => 70.0}, "files" => {}},
       {"created_at" => "2026-08-03T00:00:00Z", "branch" => nil, "commit" => nil,
        "totals" => {"line" => 100.0, "branch" => 70.0}, "files" => {"lib/a.rb" => {"line" => 75.0}}}]
    end

    # A sparkline per criterion over the whole history, then one row per
    # run: the columns are padded to the widest value so the rows line
    # up, a run with no branch or commit shows a dash, and the commit is
    # cut to seven characters.
    it "draws the totals view whole" do
      renderer.emit(out, {input: "coverage/.history.json", json: false, file: nil}, entries, color: false)

      expect(out.string).to eq(
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
      )
    end

    # The same table scoped to one path, where a run that never saw the
    # file leaves a gap in the sparkline and a dash in its row.
    it "draws one file's trajectory whole" do
      renderer.emit(out, {input: "x", json: false, file: "lib/a.rb"}, entries, color: false)

      expect(out.string).to eq(
        [
          "Coverage history for lib/a.rb (3 runs)",
          "",
          "  line  ▁ █  50.0% → 75.0%  (+25.0)",
          "",
          "  2026-08-01T00:00:00Z  main       abcdef1  line 50.0%",
          "  2026-08-02T00:00:00Z  feature-x  1234567  -",
          "  2026-08-03T00:00:00Z  -          -        line 75.0%"
        ].join("\n").concat("\n")
      )
    end

    it "says so plainly when nothing has been recorded" do
      renderer.emit(out, {input: "coverage/.history.json", json: false, file: nil}, [], color: false)

      expect(out.string).to eq("simplecov history: no recorded runs in coverage/.history.json\n")
    end

    it "emits the entries verbatim as data, and one file's rows when scoped" do
      renderer.emit(out, {input: "x", json: true, file: nil}, entries, color: false)
      expect(JSON.parse(out.string)).to eq(entries)

      scoped = StringIO.new
      renderer.emit(scoped, {input: "x", json: true, file: "lib/a.rb"}, entries, color: false)
      expect(JSON.parse(scoped.string)).to eq(
        [{"created_at" => "2026-08-01T00:00:00Z", "branch" => "main", "commit" => "abcdef1234",
          "percents" => {"line" => 50.0}},
         {"created_at" => "2026-08-02T00:00:00Z", "branch" => "feature-x", "commit" => "1234567890",
          "percents" => nil},
         {"created_at" => "2026-08-03T00:00:00Z", "branch" => nil, "commit" => nil,
          "percents" => {"line" => 75.0}}]
      )
    end

    # Scaled to the series' own range, so direction stays visible even
    # when the numbers move within a fraction of a percent. A flat
    # series renders at mid height rather than at the floor.
    it "scales the sparkline to its own range, and gaps what it has no value for" do
      expect(renderer.sparkline([1.0, 2.0, 3.0])).to eq("▁▅█")
      expect(renderer.sparkline([5.0, 5.0])).to eq("▄▄")
      expect(renderer.sparkline([1.0, nil, 3.0])).to eq("▁ █")
    end

    # A series with no numbers at all still renders, as the gaps it is.
    it "draws a series that carries no value anywhere" do
      expect(renderer.sparkline([nil, nil])).to eq("  ")
      expect(renderer.sparkline([])).to eq("")
    end

    it "reads the trend from the first and last recorded values, signed" do
      expect(renderer.trend([90.0, 100.0], false)).to eq("90.0% → 100.0%  (+10.0)")
      expect(renderer.trend([100.0, 90.0], false)).to eq("100.0% → 90.0%  (-10.0)")
      expect(renderer.trend([nil, 90.0, 90.0, nil], false)).to eq("90.0% → 90.0%  (+0.0)")
    end

    it "colours a drop red and a rise green" do
      expect(renderer.trend([100.0, 90.0], true)).to include("\e[31m(-10.0)\e[0m")
      expect(renderer.trend([90.0, 100.0], true)).to include("\e[32m(+10.0)\e[0m")
    end

    # A criterion enabled midway through the history still gets a
    # sparkline, and the criteria keep their canonical order rather than
    # the order they were first seen in.
    it "lists every criterion the history ever recorded, in order" do
      late = [{"totals" => {"branch" => 1.0}}, {"totals" => {"line" => 2.0, "method" => 3.0}}]

      expect(renderer.measured_criteria(late, ["totals"])).to eq(%w[line branch method])
      expect(renderer.measured_criteria([{"totals" => "junk"}], ["totals"])).to eq([])
      expect(renderer.measured_criteria([{"totals" => [90.0]}], ["totals"])).to eq([])
    end

    it "counts runs in words that agree with the number" do
      expect(renderer.pluralize(1, "run")).to eq("1 run")
      expect(renderer.pluralize(2, "run")).to eq("2 runs")
      expect(renderer.pluralize(0, "run")).to eq("0 runs")
    end

    it "reads only numbers as percents" do
      expect(renderer.numeric(1.5)).to eq(1.5)
      expect(renderer.numeric("1.5")).to be_nil
      expect(renderer.numeric(nil)).to be_nil
    end

    # The delta is the one colored thing in either view, and the color
    # has to survive the whole way down: the view, the sparkline row,
    # and the trend that draws the delta.
    it "colors the delta of both views when color is on" do
      renderer.emit(out, {input: "x", json: false, file: nil}, entries, color: true)

      expect(out.string).to include("90.0% → 100.0%  \e[32m(+10.0)\e[0m")
        .and include("80.0% → 70.0%  \e[31m(-10.0)\e[0m")

      scoped = StringIO.new
      renderer.emit(scoped, {input: "x", json: false, file: "lib/a.rb"}, entries, color: true)

      expect(scoped.string).to include("50.0% → 75.0%  \e[32m(+25.0)\e[0m")
    end

    # A hand-edited history: a run with none of the row's fields, a
    # percentage that is not a number, and a run that recorded nothing
    # at all. Every column still renders, the criterion nothing
    # numeric was recorded for is left out of the view entirely, and
    # the run that recorded no number for a listed criterion is a gap.
    it "draws a run that recorded none of the row's fields" do
      sparse = [{"totals" => {"line" => 90.0}}, {"totals" => {"line" => "?", "branch" => "?"}}, {}]

      renderer.emit(out, {input: "x", json: false, file: nil}, sparse, color: false)

      expect(out.string).to eq(
        [
          "Coverage history: x (3 runs)",
          "",
          "  line  ▄    90.0% → 90.0%  (+0.0)",
          "",
          "    -  -        line 90.0%",
          "    -  -        -",
          "    -  -        -"
        ].join("\n").concat("\n")
      )
    end

    # The JSON rows carry whatever the entry recorded and null where it
    # recorded nothing, including a files section holding something
    # other than a run's percentages.
    it "answers null columns for a run that recorded none of them" do
      sparse = [{}, {"files" => {"lib/a.rb" => "junk"}}]

      renderer.emit(out, {input: "x", json: true, file: "lib/a.rb"}, sparse, color: false)

      expect(JSON.parse(out.string)).to eq(
        [{"created_at" => nil, "branch" => nil, "commit" => nil, "percents" => nil},
         {"created_at" => nil, "branch" => nil, "commit" => nil, "percents" => nil}]
      )
    end

    # The label column is as wide as the widest criterion it prints,
    # not as wide as whichever one happens to come last.
    it "pads the criterion labels to the widest of them" do
      renderer.emit_sparklines(out, entries, %w[branch line], false, ["totals"])

      expect(out.string).to eq(
        ["  branch  █▁▁  80.0% → 70.0%  (-10.0)",
         "  line    ▁▅█  90.0% → 100.0%  (+10.0)"].join("\n").concat("\n")
      )
    end

    # The high and the low are read off the whole series, not off its
    # ends, and the scale between them is a float even for a history
    # that recorded whole percentages.
    it "scales to the range of the whole series" do
      expect(renderer.sparkline([3.0, 5.0, 1.0, 4.0])).to eq("▅█▁▆")
      expect(renderer.sparkline([90, 95, 100])).to eq("▁▅█")
      expect(renderer.sparkline([1.5, 2.5])).to eq("▁█")
    end

    it "rounds the delta to two decimals" do
      expect(renderer.trend([90.123456, 95.0], false)).to eq("90.123456% → 95.0%  (+4.88)")
    end
  end

  describe "history subcommand", mutant_expression: "SimpleCov::CLI::History*" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-history-spec-") }
    let(:input) { File.join(tmp, ".history.json") }

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

    # The JSON parser's complaint can run to several lines. The status
    # line takes the first, without its trailing newline.
    it "reports only the first line of a multi-line parse error" do
      File.write(input, "{\n  bad\n}")

      expect(run_history).to eq(1)
      expect(stderr.string.lines.size).to eq(1)
      expect(stderr.string).to match(/\Asimplecov history: \S.* is not valid JSON \(\S.*\)\n\z/)
    end

    # Older JSON parsers quote the offending source back, which can run
    # to several lines with whitespace around it. The status line takes
    # the first of them, trimmed.
    it "trims a multi-line parse error down to its first line" do
      File.write(input, "{}")
      allow(JSON).to receive(:parse)
        .and_raise(JSON::ParserError.new("  unexpected token at 'bad'  \nand more\n"))

      expect(run_history).to eq(1)
      expect(stderr.string).to eq("simplecov history: #{input} is not valid JSON (unexpected token at 'bad')\n")
    end

    # A run recorded before the file existed has no files section at
    # all, which is not the same as one that recorded nothing for it.
    it "carries no percents for an entry that has no files section" do
      write_history([{"created_at" => "2026-08-23T10:00:00Z", "totals" => {"line" => 90.0}},
                     entry("2026-08-24T10:00:00Z", 95.0, files: {"lib/a.rb" => {"line" => 95.0}})])

      expect(run_history("--json", "--file", "lib/a.rb")).to eq(0)
      percents = JSON.parse(stdout.string).map { |row| row["percents"] }
      expect(percents).to eq([nil, {"line" => 95.0}])
    end

    it "prints a sparkline per criterion with the run rows beneath" do
      write_history([
                      entry("2026-08-23T10:00:00Z", 90.0),
                      entry("2026-08-24T10:00:00Z", 95.0, branch: nil, commit: nil),
                      entry("2026-08-25T10:00:00Z", 100.0)
                    ])

      expect(run_history("--no-color")).to eq(0)

      expect(stdout.string).to include("Coverage history: #{input} (3 runs)")
      expect(stdout.string).to match(/line\s+▁▅█\s+90\.0% → 100\.0%\s+\(\+10\.0\)/)
      expect(stdout.string).to include("2026-08-23T10:00:00Z  main  abc123d  line 90.0%")
      expect(stdout.string).to include("2026-08-24T10:00:00Z  -     -        line 95.0%")
    end

    it "renders a flat series at mid height rather than dividing by zero" do
      write_history([entry("2026-08-23T10:00:00Z", 90.0), entry("2026-08-24T10:00:00Z", 90.0)])

      run_history("--no-color")

      expect(stdout.string).to match(/line\s+▄▄\s+90\.0% → 90\.0%\s+\(\+0\.0\)/)
    end

    it "shows every measured criterion, tolerating entries missing some or all totals" do
      first = entry("2026-08-23T10:00:00Z", 90.0)
      first["totals"]["branch"] = 80.0
      second = entry("2026-08-24T10:00:00Z", 95.0)
      second["totals"]["branch"] = 85.0
      third = entry("2026-08-25T10:00:00Z", 96.0) # no branch measurement
      fourth = entry("2026-08-26T10:00:00Z", 97.0)
      fourth["totals"] = nil # a hand-edited entry must not crash the view
      write_history([first, second, third, fourth])

      run_history("--no-color")

      expect(stdout.string).to match(/branch\s+▁█ {2}\s+80\.0% → 85\.0%\s+\(\+5\.0\)/)
      expect(stdout.string).to include("line 90.0%  branch 80.0%")
      expect(stdout.string).to include("2026-08-25T10:00:00Z  main  abc123d  line 96.0%")
    end

    it "signs a decline and renders a single run without a sparkline" do
      write_history([entry("2026-08-23T10:00:00Z", 95.0), entry("2026-08-24T10:00:00Z", 90.0)])
      run_history("--no-color")
      expect(stdout.string).to match(/line\s+█▁\s+95\.0% → 90\.0%\s+\(-5\.0\)/)

      stdout.truncate(0)
      write_history([entry("2026-08-23T10:00:00Z", 95.0)])
      run_history("--no-color")
      expect(stdout.string).to include("(1 run)")
    end

    it "follows one file's per-criterion trajectory under --file, with gaps for unrecorded runs" do
      write_history([
                      entry("2026-08-23T10:00:00Z", 90.0, files: {"lib/foo.rb" => {"line" => 50.0, "branch" => 25.0}}),
                      entry("2026-08-24T10:00:00Z", 95.0),
                      entry("2026-08-25T10:00:00Z", 100.0, files: {"lib/foo.rb" => {"line" => 100.0, "branch" => 75.0}})
                    ])

      expect(run_history("--file", "lib/foo.rb", "--no-color")).to eq(0)

      expect(stdout.string).to include("Coverage history for lib/foo.rb (3 runs)")
      expect(stdout.string).to match(/line\s+▁ █\s+50\.0% → 100\.0%\s+\(\+50\.0\)/)
      expect(stdout.string).to match(/branch\s+▁ █\s+25\.0% → 75\.0%\s+\(\+50\.0\)/)
      expect(stdout.string).to include("2026-08-23T10:00:00Z  main  abc123d  line 50.0%  branch 25.0%")
      expect(stdout.string).to include("2026-08-24T10:00:00Z  main  abc123d  -")
    end

    it "errors under --file for a file no entry recorded" do
      write_history([entry("2026-08-23T10:00:00Z", 90.0)])

      expect(run_history("--file", "lib/nope.rb")).to eq(1)
      expect(stderr.string).to include("no recorded coverage for lib/nope.rb")
    end

    # A hand-edited history can name the file under something other than
    # a run's percentages. That is a name, not a recording, and it still
    # deserves the loud answer rather than an empty sparkline.
    it "errors under --file for a file recorded as something other than percentages" do
      write_history([entry("2026-08-23T10:00:00Z", 90.0, files: {"lib/foo.rb" => "junk"})])

      expect(run_history("--file", "lib/foo.rb")).to eq(1)
      expect(stderr.string).to eq("simplecov history: no recorded coverage for lib/foo.rb in #{input}\n")
    end

    it "emits the entries as JSON" do
      write_history([entry("2026-08-23T10:00:00Z", 90.0)])

      expect(run_history("--json")).to eq(0)
      expect(JSON.parse(stdout.string).fetch(0).fetch("totals")).to eq("line" => 90.0)
    end

    it "narrows the JSON to one file's trajectory under --file" do
      write_history([
                      entry("2026-08-23T10:00:00Z", 90.0, files: {"lib/foo.rb" => {"line" => 50.0}}),
                      entry("2026-08-24T10:00:00Z", 95.0),
                      entry("2026-08-25T10:00:00Z", 96.0, files: {"lib/foo.rb" => {"line" => 60.0}})
                    ])

      run_history("--file", "lib/foo.rb", "--json")

      rows = JSON.parse(stdout.string)
      expect(rows).to eq([
                           {"created_at" => "2026-08-23T10:00:00Z", "branch" => "main",
                            "commit" => "abc123def456", "percents" => {"line" => 50.0}},
                           {"created_at" => "2026-08-24T10:00:00Z", "branch" => "main",
                            "commit" => "abc123def456", "percents" => nil},
                           {"created_at" => "2026-08-25T10:00:00Z", "branch" => "main",
                            "commit" => "abc123def456", "percents" => {"line" => 60.0}}
                         ])
    end

    it "reports an empty history plainly" do
      write_history([])

      expect(run_history).to eq(0)
      expect(stdout.string).to include("no recorded runs")
    end

    it "errors when the history file is missing" do
      expect(run_history).to eq(1)
      expect(stderr.string).to include("simplecov history:")
      expect(stderr.string).to include("not found")
      expect(stderr.string).to include("recorded automatically")
    end

    # Each refusal names the file it read, which is the only thing that
    # distinguishes them from one another in a CI log.
    it "errors when the file is not a history" do
      File.write(input, JSON.dump("something" => "else"))

      expect(run_history).to eq(1)
      expect(stderr.string).to eq("simplecov history: #{input} is not a SimpleCov history file\n")
    end

    it "errors when the file is not JSON" do
      File.write(input, "{")

      expect(run_history).to eq(1)
      expect(stderr.string).to start_with("simplecov history: #{input} is not valid JSON (")
      expect(stderr.string.lines.length).to eq(1)
    end

    it "errors when the file is JSON but not an object" do
      File.write(input, "[]")

      expect(run_history).to eq(1)
      expect(stderr.string).to eq("simplecov history: #{input} is not a SimpleCov history file\n")
    end

    it "errors when the envelope carries entries that are not a list" do
      File.write(input, JSON.dump("simplecov_history" => {"entries" => "junk"}))

      expect(run_history).to eq(1)
      expect(stderr.string).to eq("simplecov history: #{input} is not a SimpleCov history file\n")
    end

    # The history is written by the suite itself, so a missing one means
    # no suite has reported yet rather than a mistyped path.
    it "errors when the history has never been written, saying why" do
      missing = File.join(tmp, "absent.json")

      expect(run("history", "--input", missing)).to eq(1)
      expect(stderr.string).to eq(
        "simplecov history: #{missing} not found " \
        "(the history is recorded automatically each time a suite reports)\n"
      )
    end

    it "names a file the history never recorded, rather than drawing an empty line" do
      write_history([entry("2026-08-01T00:00:00Z", 90.0, files: {"lib/a.rb" => {"line" => 50.0}})])

      expect(run_history("--file", "lib/missing.rb")).to eq(1)
      expect(stderr.string).to eq("simplecov history: no recorded coverage for lib/missing.rb in #{input}\n")
    end

    it "errors when the path cannot be read as a file" do
      expect(run("history", "--input", tmp)).to eq(1)
      expect(stderr.string).to match(/\Asimplecov history: #{Regexp.escape(tmp)} could not be read \(\S.*\)\n\z/)
    end

    it "rejects a stray positional argument" do
      expect(run("history", "stray")).to eq(1)
      expect(stderr.string).to include('unexpected argument "stray"')
    end

    # The first stray argument is the one worth naming: the rest are
    # very likely the same mistake repeated.
    it "names the first of several stray arguments" do
      expect(run("history", "one", "two")).to eq(1)
      expect(stderr.string).to eq(%(simplecov history: unexpected argument "one"\n))
    end

    # The history is written beside the report, and the command finds
    # it there without being told where to look.
    it "reads the history beside the report by default" do
      allow(described_class).to receive(:coverage_dir).and_return(tmp)
      write_history([entry("2026-08-23T10:00:00Z", 90.0)])

      expect(described_class::History.default_input).to eq(input)
      expect(run("history", "--no-color")).to eq(0)
      expect(stdout.string).to include("Coverage history: #{input} (1 run)")
    end

    # A parser complaint with nothing in it still leaves a status line
    # that reads as one, rather than taking the read down with it.
    it "prints an empty parser complaint as an empty note" do
      File.write(input, "{}")
      allow(JSON).to receive(:parse).and_raise(JSON::ParserError.new(""))

      expect(run_history).to eq(1)
      expect(stderr.string).to eq("simplecov history: #{input} is not valid JSON ()\n")
    end

    # The entries are whatever the file held. One that is not an object
    # records nothing for any file, and must not take the lookup down
    # with it.
    it "reads past an entry that is not an object when looking for a file" do
      write_history(["junk"])

      expect(run_history("--file", "lib/a.rb")).to eq(1)
      expect(stderr.string).to eq("simplecov history: no recorded coverage for lib/a.rb in #{input}\n")
    end

    # The answer is a plain yes or no: `run` reads it as the difference
    # between reporting and carrying on.
    it "answers whether the file was recorded at all" do
      opts = {file: "lib/a.rb", input: input}

      expect(described_class::History.file_recorded?([], opts, stderr)).to be(false)
      expect(described_class::History.file_recorded?([], {file: nil, input: input}, stderr)).to be(true)
    end

    context "with colorization" do
      it "colors the trend when Color.enabled? is true" do
        allow(SimpleCov::Color).to receive(:enabled?).and_return(true)
        write_history([entry("2026-08-23T10:00:00Z", 90.0), entry("2026-08-24T10:00:00Z", 95.0)])

        expect(run_history).to eq(0)
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
    let(:input) { File.join(tmp, "coverage.json") }
    let(:production_path) { File.join(tmp, "production.json") }

    before do
      # L1 tested+prod (normal), L2 untested+unprod (dead), L4
      # tested+unprod (possibly dead), L5 untested+prod (untested in
      # production). tested_unused.rb is fully tested and never runs in
      # production. ignored/irrelevant lines stay out of every bucket.
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

    # A hand-written production file, for the shapes a sink would not
    # write but a reader still meets.
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

      # Whole output: the header, the blank line under it, both headings
      # with their rows, the blank line after each, and the summary.
      it "prints each section under its heading, and counts them at the end" do
        expect(run_dead_code).to eq(0)
        expect(stdout.string).to eq(<<~REPORT)
          Production coverage: #{production_path} (window 2026-01-01T00:00:00Z to 2026-02-01T00:00:00Z)

          Dead code (not run in production, not covered by tests):
            lib/dead.rb:1 (entire file)

          Possibly dead (not run in production, covered only by tests):
            lib/possible.rb:1 (entire file)

          1 dead line, 1 possibly dead line
        REPORT
      end

      it "lists the files in a category in a settled order" do
        File.write(input, JSON.dump("coverage" => {"lib/zebra.rb" => {"lines" => [0]},
                                                   "lib/apple.rb" => {"lines" => [0]}}))

        expect(run_dead_code).to eq(0)
        listed = stdout.string.lines.grep(/\.rb:/).map(&:strip)
        expect(listed.first).to start_with("lib/apple.rb:")
        expect(listed.last).to start_with("lib/zebra.rb:")
      end

      it "prints neither heading nor blank line for a category with nothing in it" do
        File.write(input, JSON.dump("coverage" => {"lib/dead.rb" => {"lines" => [0]}}))

        expect(run_dead_code).to eq(0)
        expect(stdout.string).not_to include("Possibly dead")
      end

      it "says so plainly when there is nothing to report" do
        File.write(input, JSON.dump("coverage" => {}))

        expect(run_dead_code).to eq(0)
        expect(stdout.string).to eq(<<~REPORT)
          Production coverage: #{production_path} (window 2026-01-01T00:00:00Z to 2026-02-01T00:00:00Z)

          No dead code found.
        REPORT
      end

      it "says so plainly when nothing untested is running in production" do
        File.write(input, JSON.dump("coverage" => {}))

        expect(run_dead_code("--untested-in-production")).to eq(0)
        expect(stdout.string).to end_with("No untested production code found.\n")
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

      # Half a window is not a window, so neither half alone is named.
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

        expect(run_dead_code("--json")).to eq(0)
        expect(JSON.parse(stdout.string)).to eq(
          "window" => {"started_at" => "2026-01-01T00:00:00Z", "updated_at" => "2026-02-01T00:00:00Z"},
          "dead" => [{"file" => "lib/apple.rb", "lines" => [1], "last_seen" => "2026-03-04T05:06:07Z"},
                     {"file" => "lib/zebra.rb", "lines" => [1]}],
          "possibly_dead" => [], "untested_in_production" => []
        )
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

        expect(run_dead_code).to eq(0)
        expect(stdout.string).to include("No dead code found.")
      end

      # Nothing relevant was measured, so nothing about the file is
      # known, and a file nothing is known about is not a candidate for
      # deletion.
      it "does not call a file with no relevant lines entirely dead" do
        File.write(input, JSON.dump("coverage" => {"lib/blank.rb" => {"lines" => [nil, nil]}}))

        expect(run_dead_code).to eq(0)
        expect(stdout.string).not_to include("entire file")
      end

      it "calls a file entirely dead only when every relevant line is unhit" do
        File.write(input, JSON.dump("coverage" => {"lib/all.rb" => {"lines" => [0, 1]}}))
        SimpleCov::Production::FileSink.new(path: production_path).store("lib/other.rb" => [1])

        expect(run_dead_code).to eq(0)
        expect(stdout.string).to include("entire file")
      end

      it "leaves a file with one line still running out of the entire-file mark" do
        File.write(input, JSON.dump("coverage" => {"lib/some.rb" => {"lines" => [0, 1]}}))
        SimpleCov::Production::FileSink.new(path: production_path).store("lib/some.rb" => [2])

        expect(run_dead_code).to eq(0)
        expect(stdout.string).not_to include("entire file")
      end
    end

    describe "reporting what it could not read" do
      it "names the report it could not find, under its own name" do
        expect(run("dead-code", "--input", File.join(tmp, "absent.json"),
                   "--production", production_path)).to eq(1)
        expect(stderr.string).to eq("simplecov dead-code: #{File.join(tmp, 'absent.json')} not found\n")
      end

      it "names the production file it could not find" do
        absent = File.join(tmp, "absent-production.json")

        expect(run("dead-code", "--input", input, "--production", absent)).to eq(1)
        expect(stderr.string).to eq("simplecov dead-code: #{absent} not found\n")
      end

      it "reports what was wrong with a production file it could not read" do
        File.write(production_path, "not json at all")

        expect(run_dead_code).to eq(1)
        expect(stderr.string).to start_with("simplecov dead-code:")
        expect(stderr.string).not_to include("#<")
      end

      it "refuses a stray positional argument, naming the first one" do
        expect(run_dead_code("stray", "another")).to eq(1)
        expect(stderr.string).to eq("simplecov dead-code: unexpected argument \"stray\"\n")
      end
    end

    # A hand-written store can carry a file's lines in any order; the
    # row that reports them puts them in reading order.
    it "sorts the lines of a file the report never tracked" do
      File.write(input, JSON.dump("coverage" => {}))
      write_production(coverage: {"lib/prod_only.rb" => [9, 2, 5]})

      expect(run_dead_code("--untested-in-production")).to eq(0)
      expect(stdout.string).to include("lib/prod_only.rb:2,5,9")
    end

    # Files the report never tracked are listed in a settled order, and
    # so are the lines within each.
    it "sorts the production-only files and their lines" do
      File.write(input, JSON.dump("coverage" => {}))
      SimpleCov::Production::FileSink.new(path: production_path).store(
        "lib/zebra.rb" => [9, 2], "lib/apple.rb" => [4]
      )

      expect(run_dead_code("--untested-in-production")).to eq(0)
      listed = stdout.string.lines.grep(/\.rb:/).map(&:strip)
      expect(listed.first).to start_with("lib/apple.rb:4")
      expect(listed.last).to start_with("lib/zebra.rb:2,9")
    end

    def run_dead_code(*extra)
      run("dead-code", "--input", input, "--production", production_path, *extra)
    end

    # The date the store last saw a file run, as the text views print it.
    def last_run(file)
      SimpleCov::Production::FileSink.read(production_path).fetch("last_seen").fetch(file)[0, 10]
    end

    it "prints the dead and possibly dead rows with ranges and a summary" do
      expect(run_dead_code).to eq(0)

      expect(stdout.string).to include("Dead code (not run in production, not covered by tests):")
      expect(stdout.string).to include("  lib/mixed.rb:2 (last run #{last_run('lib/mixed.rb')})\n")
      expect(stdout.string).to include("Possibly dead (not run in production, covered only by tests):")
      expect(stdout.string).to include("  lib/mixed.rb:4 (last run #{last_run('lib/mixed.rb')})\n")
      expect(stdout.string).to include("1 dead line, 3 possibly dead lines")
    end

    it "marks a file whose every relevant line skipped production, and keeps the other rows out" do
      run_dead_code

      expect(stdout.string).to include("  lib/tested_unused.rb:1-2 (entire file)\n")
      expect(stdout.string).not_to include("prod_only")
      expect(stdout.string).not_to include("ignored.rb")
    end

    # A store can have seen a file without any of its relevant lines
    # (stale line numbers, lines the report deems irrelevant): the row
    # then carries both markers, because "every relevant line skipped
    # production" and "production last touched this file in August" are
    # both evidence.
    it "combines the entire-file marker with the file's last production activity" do
      SimpleCov::Production::FileSink.new(path: production_path).store("lib/tested_unused.rb" => [9])

      run_dead_code

      expect(stdout.string)
        .to include("  lib/tested_unused.rb:1-2 (entire file, last run #{last_run('lib/tested_unused.rb')})\n")
    end

    # A v1 store (or a remote sink that only fills the documented shape)
    # carries no stamps; rows stay bare rather than guessing.
    it "leaves the annotation off when the store carries no stamps" do
      document = JSON.parse(File.read(production_path))
      document[SimpleCov::Production::FileSink::ENVELOPE].delete("last_seen")
      File.write(production_path, JSON.dump(document))

      expect(run_dead_code).to eq(0)
      expect(stdout.string).to include("  lib/mixed.rb:2\n")
      expect(stdout.string).not_to include("last run")
    end

    it "names the production file and its window in the header" do
      run_dead_code

      window = SimpleCov::Production::FileSink.read(production_path)
      expect(stdout.string).to include("Production coverage: #{production_path}")
      expect(stdout.string).to include("window #{window.fetch('started_at')} to #{window.fetch('updated_at')}")
    end

    it "prints the untested-in-production row under --untested-in-production" do
      expect(run_dead_code("--untested-in-production")).to eq(0)

      expect(stdout.string).to include("Untested code running in production:")
      expect(stdout.string).to include("  lib/mixed.rb:5 (last run #{last_run('lib/mixed.rb')})\n")
      expect(stdout.string).to include("  lib/prod_only.rb:3-4 (last run #{last_run('lib/prod_only.rb')})\n")
      expect(stdout.string).to include("3 untested lines running in production")
      expect(stdout.string).not_to include("Dead code")
    end

    it "emits every category as JSON, with the full stamps" do
      expect(run_dead_code("--json")).to eq(0)

      store = SimpleCov::Production::FileSink.read(production_path).fetch("last_seen")
      data = JSON.parse(stdout.string)
      expect(data.fetch("dead"))
        .to eq([{"file" => "lib/mixed.rb", "lines" => [2], "last_seen" => store.fetch("lib/mixed.rb")}])
      expect(data.fetch("possibly_dead")).to eq(
        [{"file" => "lib/mixed.rb", "lines" => [4], "last_seen" => store.fetch("lib/mixed.rb")},
         {"file" => "lib/tested_unused.rb", "lines" => [1, 2]}]
      )
      expect(data.fetch("untested_in_production")).to eq(
        [{"file" => "lib/mixed.rb", "lines" => [5], "last_seen" => store.fetch("lib/mixed.rb")},
         {"file" => "lib/prod_only.rb", "lines" => [3, 4], "last_seen" => store.fetch("lib/prod_only.rb")}]
      )
      expect(data.fetch("window")).to include("started_at", "updated_at")
    end

    it "reports the happy emptiness when nothing is dead" do
      SimpleCov::Production::FileSink.new(path: production_path).store(
        "lib/mixed.rb" => [2, 4], "lib/tested_unused.rb" => [1, 2]
      )

      expect(run_dead_code).to eq(0)
      expect(stdout.string).to include("No dead code found.")
    end

    it "reports the happy emptiness for the untested view too" do
      FileUtils.rm(production_path)
      SimpleCov::Production::FileSink.new(path: production_path).store("lib/mixed.rb" => [1, 4])

      expect(run_dead_code("--untested-in-production")).to eq(0)
      expect(stdout.string).to include("No untested production code found.")
    end

    # A branch-only report carries entries without a "lines" array;
    # those files simply cannot be classified.
    it "skips report entries without line data" do
      File.write(input, JSON.dump("coverage" => {"lib/branch_only.rb" => {"branches" => []}}))

      expect(run_dead_code).to eq(0)
      expect(stdout.string).not_to include("branch_only")
    end

    it "omits the window from the header when the store carries no timestamps" do
      File.write(production_path, JSON.dump(
                                    SimpleCov::Production::FileSink::ENVELOPE => {
                                      "format_version" => 1, "coverage" => {"lib/mixed.rb" => [1]}
                                    }
                                  ))

      expect(run_dead_code).to eq(0)
      expect(stdout.string).to include("Production coverage: #{production_path}\n")
      expect(stdout.string).not_to include("window")
    end

    it "defaults --production to the project's configured production_coverage" do
      File.write(File.join(tmp, ".simplecov"), %(SimpleCov.production_coverage #{production_path.inspect}\n))

      Dir.chdir(tmp) { expect(run("dead-code", "--input", input)).to eq(0) }
      expect(stdout.string).to include("Production coverage: #{production_path}")
    end

    it "prefers an explicit --production over the configured store" do
      other = File.join(tmp, "other.json")
      SimpleCov::Production::FileSink.new(path: other).store("lib/other.rb" => [1])
      File.write(File.join(tmp, ".simplecov"), %(SimpleCov.production_coverage #{other.inspect}\n))

      Dir.chdir(tmp) { expect(run_dead_code).to eq(0) }
      expect(stdout.string).to include("Production coverage: #{production_path}")
      expect(stdout.string).not_to include("other.json")
    end

    it "errors without --production when the project configures no store" do
      Dir.chdir(tmp) { expect(run("dead-code", "--input", input)).to eq(1) }
      expect(stderr.string).to include("simplecov dead-code: missing --production")
      expect(stderr.string).to include("production_coverage")
    end

    it "errors when the production file is missing" do
      FileUtils.rm(production_path)

      expect(run_dead_code).to eq(1)
      expect(stderr.string).to include("simplecov dead-code:")
      expect(stderr.string).to include("not found")
    end

    it "errors when the production file is not a production store" do
      File.write(production_path, JSON.dump("coverage" => {}))

      expect(run_dead_code).to eq(1)
      expect(stderr.string).to include("not a SimpleCov production coverage file")
    end

    it "rejects a stray positional argument" do
      expect(run("dead-code", "--production", production_path, "stray")).to eq(1)
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

    # The suffix carries a leading slash so a subpath matches whole path
    # segments rather than the tail of a longer name.
    it "does not let a subpath match the end of a longer filename" do
      expect(lookup({"/x/barfoo.rb" => "V"}, "foo.rb")).to be_nil
      expect(lookup({"/x/foo.rb" => "V"}, "foo.rb")).to eq(["/x/foo.rb", "V"])
    end

    describe "the failure message" do
      def message(hash, path)
        SimpleCov::CLI::CoverageFile.not_found_message(hash, path, "coverage/coverage.json")
      end

      # An ambiguous subpath names its candidates: "no entry" would send
      # someone hunting for a typo in a path that exists twice.
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

      # One match is not an ambiguity: it resolved, and any later failure
      # is about something else.
      it "reports a single suffix match as absent rather than ambiguous" do
        expect(message({"/x/lib/a.rb" => "V"}, "lib/a.rb"))
          .to eq("no entry for lib/a.rb in coverage/coverage.json")
      end
    end

    # The exact index is what `patch` resolves changed files through,
    # where a suffix fallback could bind a path to the wrong entry.
    describe "the exact index" do
      def index(hash)
        SimpleCov::CLI::CoverageFile.exact_index(hash)
      end

      it "holds every key under its own spelling" do
        expect(index({"lib/a.rb" => "A", "lib/b.rb" => "B"}))
          .to include("lib/a.rb" => "A", "lib/b.rb" => "B")
      end

      # A symlinked root (macOS puts temporary directories behind one)
      # would otherwise split a resolved path from the report's key.
      it "holds a real path under its resolved spelling too" do
        Dir.mktmpdir("simplecov-exact-index-") do |dir|
          file = File.join(dir, "a.rb")
          File.write(file, "x")

          built = index({file => "A"})

          expect(built[file]).to eq("A")
          expect(built[File.realdirpath(file)]).to eq("A")
        end
      end

      it "keeps the literal spelling of a key whose file is gone" do
        expect(index({"/nonexistent/gone.rb" => "A"})).to eq("/nonexistent/gone.rb" => "A")
      end

      # First writer wins, so a key reached through a symlink cannot
      # replace the entry that already claimed the resolved spelling.
      it "lets the first entry keep a spelling two keys share" do
        Dir.mktmpdir("simplecov-exact-index-link-") do |dir|
          real = File.join(dir, "real")
          FileUtils.mkdir_p(real)
          File.write(File.join(real, "a.rb"), "x")
          FileUtils.ln_s(real, File.join(dir, "linked"))

          built = index(File.join(real, "a.rb") => "REAL", File.join(dir, "linked", "a.rb") => "VIA_LINK")

          expect(built[File.realdirpath(File.join(real, "a.rb"))]).to eq("REAL")
          expect(built[File.join(dir, "linked", "a.rb")]).to eq("VIA_LINK")
        end
      end
    end

    describe "reporting an unusable input file" do
      let(:stderr) { StringIO.new }

      it "names a missing file under the command that looked for it" do
        expect(SimpleCov::CLI::CoverageFile.load_document("/nope.json", command: "report", stderr: stderr))
          .to be_nil
        expect(stderr.string).to eq("simplecov report: /nope.json not found\n")
      end

      it "names an unreadable file and the reason, on one line" do
        Dir.mktmpdir("simplecov-unreadable-") do |dir|
          expect(SimpleCov::CLI::CoverageFile.load_document(dir, command: "report", stderr: stderr)).to be_nil
          expect(stderr.string).to start_with("simplecov report: cannot read #{dir.inspect} (")
          expect(stderr.string.lines.length).to eq(1)
        end
      end

      it "reduces a multi-line reason to its first line" do
        SimpleCov::CLI::CoverageFile.report_invalid(stderr, "report", "x.json", "first line\nsecond line")

        expect(stderr.string).to eq(%(simplecov report: input file "x.json" isn't valid JSON (first line)\n))
      end

      # Trimmed at both ends: a parser's message often arrives indented,
      # and the reason sits inside parentheses where that would show.
      it "trims the reason at both ends, not just the right" do
        SimpleCov::CLI::CoverageFile.report_invalid(stderr, "report", "x.json", "  padded  \nrest")

        expect(stderr.string).to eq(%(simplecov report: input file "x.json" isn't valid JSON (padded)\n))
      end

      it "trims an unreadable reason at both ends too" do
        SimpleCov::CLI::CoverageFile.report_unreadable(stderr, "report", "x.json", "  padded  \nrest")

        expect(stderr.string).to eq(%(simplecov report: cannot read "x.json" (padded)\n))
      end

      # A document with no coverage section at all reads as an empty one
      # rather than as a malformed report.
      it "reads a document with no coverage section as carrying none" do
        Dir.mktmpdir("simplecov-no-coverage-") do |dir|
          path = File.join(dir, "coverage.json")
          File.write(path, JSON.dump("meta" => {}))

          expect(SimpleCov::CLI::CoverageFile.load_coverage(path, command: "report", stderr: stderr)).to eq({})
          expect(stderr.string).to be_empty
        end
      end

      # An exception with an empty message still has to produce a line
      # rather than raise from inside the error path.
      it "reports a reason that is empty" do
        SimpleCov::CLI::CoverageFile.report_invalid(stderr, "report", "x.json", "")

        expect(stderr.string).to eq(%(simplecov report: input file "x.json" isn't valid JSON ()\n))
      end

      it "reports an unreadable reason that is empty" do
        SimpleCov::CLI::CoverageFile.report_unreadable(stderr, "report", "x.json", "")

        expect(stderr.string).to eq(%(simplecov report: cannot read "x.json" ()\n))
      end

      # Any Hash of coverage will do, including one a document reader
      # hands back as a subclass of it.
      # The command name is what tells one refusal from another in a log,
      # so the coverage-section refusal carries it too.
      it "names the command when refusing a coverage section" do
        Dir.mktmpdir("simplecov-bad-coverage-") do |dir|
          path = File.join(dir, "coverage.json")
          File.write(path, JSON.dump("coverage" => "junk"))

          SimpleCov::CLI::CoverageFile.load_coverage(path, command: "uncovered", stderr: stderr)

          expect(stderr.string)
            .to eq(%(simplecov uncovered: input file #{path.inspect} isn't valid JSON ("coverage" must be an object)\n))
        end
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

  # The rendering half of `patch`, driven directly: the command's own
  # examples build a git repository per case, which is the wrong shape
  # for pinning the layout of every cell, note, and total.
  # Tagged for the renderer alone, which makes these the tests its
  # subjects answer to: they exercise it directly, where the
  # subcommand's own examples reach it through a built git repository.
  describe "patch output", mutant_expression: "SimpleCov::CLI::Patch::Output*" do
    let(:renderer) { SimpleCov::CLI::Patch::Output }
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

    # Worst first, every cell aligned, the missing ranges collapsed, and
    # a criterion the touched lines never carried left out rather than
    # printed as a hollow 0/0.
    it "prints the rows worst first, with a total beneath them" do
      renderer.emit_text(stdout, rows, false)

      # Written as literal lines rather than a squiggly heredoc, whose
      # indent stripping would eat the two-space gutter under test.
      expect(stdout.string).to eq(
        [
          "   88.00% (22/25) lines   50.00% (1/2) branches  lib/a.rb  missing 41-43, 47  branch 39",
          "  100.00% (4/4) lines  lib/b.rb",
          "  Patch coverage:  89.66% (26/29) lines,  50.00% (1/2) branches"
        ].join("\n").concat("\n")
      )
    end

    it "sorts by coverage first and by filename only to break a tie" do
      unsorted = [
        {file: "a.rb", line: {covered: 1, relevant: 1, missing: []}, branch: nil, method: nil},
        {file: "z.rb", line: {covered: 0, relevant: 2, missing: [1, 2]}, branch: nil, method: nil},
        {file: "m.rb", line: {covered: 0, relevant: 2, missing: [1, 2]}, branch: nil, method: nil}
      ]
      renderer.emit_text(stdout, unsorted, false)

      expect(stdout.string.lines.filter_map { |line| line[/\S+\.rb/] }).to eq(["m.rb", "z.rb", "a.rb"])
    end

    it "totals every criterion the rows measured, methods included" do
      with_methods = rows.collect do |row|
        row.merge(method: {covered: 1, relevant: 2, missing: [8]})
      end
      renderer.emit_text(stdout, with_methods, false)

      expect(stdout.string.lines.last)
        .to eq("  Patch coverage:  89.66% (26/29) lines,  50.00% (1/2) branches,  50.00% (2/4) methods\n")
    end

    it "says so plainly when the change touched no coverable line" do
      renderer.emit_text(stdout, [], false)

      expect(stdout.string).to eq("simplecov patch: no coverable lines changed\n")
    end

    it "emits the same rows as data, each criterion carrying its percent" do
      expect(renderer.json_rows(rows)).to eq(
        [{file: "lib/a.rb",
          line: {covered: 22, relevant: 25, missing: [41, 42, 43, 47], percent: 88.0},
          branch: {covered: 1, relevant: 2, missing: [39], percent: 50.0}},
         {file: "lib/b.rb",
          line: {covered: 4, relevant: 4, missing: [], percent: 100.0}}]
      )
    end

    it "collapses runs of lines into ranges, and single lines into themselves" do
      expect(renderer.ranges([41, 42, 43, 47])).to eq("41-43, 47")
      expect(renderer.ranges([1])).to eq("1")
      expect(renderer.ranges([1, 3, 5])).to eq("1, 3, 5")
      expect(renderer.ranges([1, 2])).to eq("1-2")
    end

    # The show subcommand borrows this with a bare comma for its
    # greppable form, so the separator has to reach the joins.
    it "joins the ranges with the separator it was given" do
      expect(renderer.ranges([1, 3], ",")).to eq("1,3")
      expect(renderer.ranges([1, 3])).to eq("1, 3")
      expect(renderer.ranges([1, 2, 3], ",")).to eq("1-3")
    end

    it "scores a change that touched nothing relevant as complete" do
      expect(renderer.pct(covered: 0, relevant: 0)).to eq(100.0)
      expect(renderer.pct(covered: 1, relevant: 3)).to eq(33.33)
    end

    # Branch stats are nil on rows from a line-only report, and 0/0 when
    # the change touched none: neither counts as measured.
    it "counts only the rows that measured a criterion into its total" do
      expect(renderer.sum_stats(rows, :branch)).to eq(covered: 1, relevant: 2)
      expect(renderer.sum_stats(rows, :line)).to eq(covered: 26, relevant: 29)
      expect(renderer.measured?(nil)).to be false
      expect(renderer.measured?(covered: 0, relevant: 0)).to be false
      expect(renderer.measured?(covered: 0, relevant: 1)).to be true
    end

    it "colorizes a shortfall red and a full cell green" do
      renderer.emit_text(stdout, rows, true)

      expect(stdout.string).to include("\e[31m 88.00%\e[0m").and include("\e[32m100.00%\e[0m")
    end

    # The total is a row like any other, so it takes the same colour.
    it "colorizes the total line too" do
      renderer.emit_text(stdout, rows, true)

      expect(stdout.string.lines.last).to include("\e[31m 89.66%\e[0m")
    end

    it "counts a Hash subclass of statistics as measured" do
      expect(renderer.measured?(Class.new(Hash).new.merge!(covered: 0, relevant: 1))).to be true
    end

    # Full is full, and nothing short of it counts: a cell at or past
    # complete is green, and one a fraction below is not.
    it "colours a cell at or past complete green, and anything below red" do
      expect(renderer.criterion_cell("lines", {covered: 3, relevant: 2, missing: []}, true))
        .to include("\e[32m")
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

    # Whether colour is on is decided from the stream being written to,
    # so the stream is what has to be asked about.
    it "asks about the stream it is writing to" do
      allow(described_class).to receive(:color_enabled?).and_return(false)

      renderer.emit(stdout, rows, json: false)

      expect(described_class).to have_received(:color_enabled?).with({json: false}, stdout)
    end

    # A criterion that measured nothing has no missing lines to name,
    # however its stats hash is shaped.
    it "notes nothing for a criterion that measured nothing" do
      row = {file: "f", line: {covered: 1, relevant: 1, missing: []},
             branch: {covered: 0, relevant: 0, missing: [3]}, method: nil}

      expect(renderer.missing_note(row)).to eq("")
    end

    # A criterion the change touched none of is still a Hash, so the
    # cell is left out on what it measured rather than on its presence.
    it "leaves out a branch cell the change touched none of" do
      row = {file: "f", line: {covered: 1, relevant: 1, missing: []},
             branch: {covered: 0, relevant: 0, missing: []}, method: nil}

      expect(renderer.criterion_cells(row, false)).to eq(["100.00% (1/1) lines"])
    end

    describe "emit" do
      it "prints the rows as data under --json, and as text otherwise" do
        renderer.emit(stdout, rows, json: true)
        expect(JSON.parse(stdout.string)).to eq(
          [{"file" => "lib/a.rb",
            "line" => {"covered" => 22, "relevant" => 25, "missing" => [41, 42, 43, 47], "percent" => 88.0},
            "branch" => {"covered" => 1, "relevant" => 2, "missing" => [39], "percent" => 50.0}},
           {"file" => "lib/b.rb",
            "line" => {"covered" => 4, "relevant" => 4, "missing" => [], "percent" => 100.0}}]
        )

        plain = StringIO.new
        renderer.emit(plain, rows, json: false, no_color: true)
        expect(plain.string).to start_with("   88.00%")
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

    # The exit status of `patch --minimum N`. The arithmetic is
    # cross-multiplied rather than compared as percentages, so the
    # boundary cases the code reasons about are the ones asserted here.
    describe "the minimum gate" do
      def row(covered, relevant, criterion: :line)
        base = {file: "lib/a.rb", line: {covered: 0, relevant: 0, missing: []}, branch: nil, method: nil}
        base.merge(criterion => {covered: covered, relevant: relevant, missing: []})
      end

      it "reports without gating when no minimum was asked for" do
        expect(renderer.gate([row(0, 10)], nil)).to eq(0)
      end

      it "passes a patch that clears the floor and fails one that does not" do
        expect(renderer.gate([row(9, 10)], 90)).to eq(0)
        expect(renderer.gate([row(8, 10)], 90)).to eq(1)
      end

      it "holds every measured criterion to the floor, not just lines" do
        expect(renderer.gate([row(10, 10).merge(branch: {covered: 0, relevant: 2, missing: []})], 100)).to eq(1)
        expect(renderer.gate([row(10, 10).merge(method: {covered: 0, relevant: 1, missing: []})], 100)).to eq(1)
      end

      it "never fails a criterion the change touched none of" do
        expect(renderer.short?({covered: 0, relevant: 0}, 100)).to be false
        expect(renderer.gate([row(10, 10)], 100)).to eq(0)
      end

      # Rounding the displayed percent would pass this against 100.
      it "fails a patch that is short by a line however small the shortfall" do
        expect(renderer.short?({covered: 19_999, relevant: 20_000}, 100)).to be true
      end

      # Float division makes 23/40 compute as 57.4999…, which would fail
      # a patch that is exactly at the floor.
      it "passes a patch sitting exactly on the floor" do
        expect(renderer.short?({covered: 23, relevant: 40}, 57.5)).to be false
      end

      # 64.4 is not representable in binary, so 64.4 * 250 lands just
      # above the integer the patch actually reached.
      it "passes a floor whose decimal has no exact binary form" do
        expect(renderer.short?({covered: 161, relevant: 250}, 64.4)).to be false
      end
    end

    describe "the cells and notes a row carries" do
      it "prints a branch or method cell only when the change touched one" do
        both = {file: "f", line: {covered: 1, relevant: 2, missing: [2]},
                branch: {covered: 1, relevant: 4, missing: [3]},
                method: {covered: 3, relevant: 4, missing: [7]}}
        expect(renderer.criterion_cells(both, false))
          .to eq([" 50.00% (1/2) lines", " 25.00% (1/4) branches", " 75.00% (3/4) methods"])

        neither = both.merge(branch: nil, method: {covered: 0, relevant: 0, missing: []})
        expect(renderer.criterion_cells(neither, false)).to eq([" 50.00% (1/2) lines"])
      end

      it "notes the missing lines, then each measured criterion's own" do
        row = {file: "f", line: {covered: 0, relevant: 2, missing: [1, 2]},
               branch: {covered: 0, relevant: 1, missing: [5]},
               method: {covered: 0, relevant: 1, missing: [9]}}
        expect(renderer.missing_note(row)).to eq("missing 1-2  branch 5  method 9")
      end

      # A criterion can be measured and still have nothing missing, and
      # an empty range list would print a bare label with no lines.
      it "notes only the criteria that actually missed something" do
        row = {file: "f", line: {covered: 2, relevant: 2, missing: []},
               branch: {covered: 2, relevant: 2, missing: []},
               method: {covered: 0, relevant: 1, missing: [4]}}
        expect(renderer.missing_note(row)).to eq("method 4")
      end

      it "says nothing about a row with nothing missing" do
        row = {file: "f", line: {covered: 1, relevant: 1, missing: []}, branch: nil, method: nil}
        expect(renderer.missing_note(row)).to eq("")
        expect(renderer.format_row(row, false)).to eq("  100.00% (1/1) lines  f")
      end
    end
  end

  describe "patch subcommand", mutant_expression: "SimpleCov::CLI::Patch*" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-patch-spec-") }
    let(:cov) { File.join(tmp, "coverage.json") }

    # rm_rf rather than remove_entry: it shrugs off files a lingering
    # background git process deletes mid-walk instead of raising ENOENT.
    after { FileUtils.rm_rf(tmp) }

    def git(*args)
      output, status = Open3.capture2e("git", "-C", tmp, *args)
      raise "git #{args.join(' ')} failed: #{output}" unless status.success?

      output
    end

    # A one-file repo whose HEAD (on a `feature` branch) differs from
    # `main`, plus a coverage.json whose `lines` array (indexed from line 1)
    # reflects `line_hits`. HEAD lives on its own branch so `main...HEAD`
    # resolves to the change rather than to an empty merge-base diff.
    def build_repo(base:, head:, line_hits:, branches: nil, methods: nil, file: "lib/foo.rb", cover: true)
      init_repo
      write(file, base)
      commit("base")
      git("checkout", "-q", "-b", "feature")
      write(file, head)
      commit("head")
      write_report(file, line_hits, branches, methods) if cover
    end

    # One git process rather than five. The settings are appended to the
    # config file the init just wrote, which is the same file four
    # `git config` runs would have edited one line at a time. The empty
    # template keeps git from copying its sixteen sample hooks into
    # every repository an example builds.
    #
    # git 2.46+ forks a detached `git maintenance` after commits; its
    # transient .git/objects/maintenance.lock races the after-hook's
    # directory removal, so the fixture repo opts out of both.
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

    it "reports coverage over only the touched lines" do
      build_repo(base: "a\n", head: "a\nb\nc\n", line_hits: [1, 1, 0])

      expect(run_in_repo("patch", "--base", "main", "--input", cov)).to eq(0)
      expect(stdout.string).to include("(1/2)").and include("missing 3")
      expect(stdout.string).to match(%r{Patch coverage:\s+50\.00%\s+\(1/2\)})
    end

    it "collapses consecutive missed lines into a range" do
      build_repo(base: "a\n", head: "a\nb\nc\nd\n", line_hits: [1, 0, 0, 0])

      run_in_repo("patch", "--base", "main", "--input", cov)
      expect(stdout.string).to include("missing 2-4")
    end

    it "excludes never-relevant touched lines from the denominator" do
      # line 2 is a comment (nil in the lines array) -> not counted
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
      expect(stdout.string).to match(%r{50\.00%\s+\(1/2\)\s+branches})
      expect(stdout.string).to include("branch 2")
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
      expect(stdout.string).to match(%r{50\.00%\s+\(1/2\)\s+methods})
      expect(stdout.string).to include("method 3")
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

    it "omits the branch and method columns for a line-only report" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])

      run_in_repo("patch", "--base", "main", "--input", cov)
      expect(stdout.string).not_to include("branches")
      expect(stdout.string).not_to include("methods")
    end

    it "skips changed files the report does not track" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 0], file: "README.md", cover: false)
      write_coverage(File.join(tmp, "lib/other.rb") => [1])

      expect(run_in_repo("patch", "--base", "main", "--input", cov)).to eq(0)
      expect(stdout.string).to include("no coverable lines changed")
    end

    it "errors when the base ref cannot be resolved" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 0])

      expect(run_in_repo("patch", "--base", "does-not-exist", "--input", cov)).to eq(1)
      expect(stderr.string).to include("could not run `git diff`")
    end

    it "resolves an omitted --base through origin's HEAD" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])
      allow(SimpleCov::CLI::Git).to receive(:default_base).and_return("main")

      expect(run_in_repo("patch", "--input", cov)).to eq(0)
      expect(SimpleCov::CLI::Git).to have_received(:default_base)
    end

    it "errors when the coverage input is missing" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 0], cover: false)

      expect(run_in_repo("patch", "--base", "main", "--input", cov)).to eq(1)
      expect(stderr.string).to include(cov).and include("not found")
    end

    it "skips colorization when --no-color is passed, even with Color.enabled? on" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])
      allow(SimpleCov::Color).to receive(:enabled?).and_return(true)

      expect(run_in_repo("patch", "--base", "main", "--input", cov, "--no-color")).to eq(0)
      expect(stdout.string).not_to be_empty
      expect(stdout.string).not_to include("\e[")
    end

    it "follows a renamed file under --find-renames" do
      init_repo
      write("lib/old.rb", "a\nb\n")
      commit("base")
      git("checkout", "-q", "-b", "feature")
      git("mv", "lib/old.rb", "lib/new.rb")
      write("lib/new.rb", "a\nb\nc\n")
      commit("rename")
      write_report("lib/new.rb", [1, 1, 0], nil)

      expect(run_in_repo("patch", "--base", "main", "--input", cov, "--find-renames")).to eq(0)
      expect(stdout.string).to include("lib/new.rb").and include("missing 3")
    end

    it "reports a git failure when git cannot be launched" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])
      allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT.new("git"))

      expect(run_in_repo("patch", "--base", "main", "--input", cov)).to eq(1)
      expect(stderr.string).to include("could not run `git diff`")
    end

    it "ignores a pure-deletion hunk" do
      build_repo(base: "a\nb\nc\n", head: "a\n", line_hits: [1])

      expect(run_in_repo("patch", "--base", "main", "--input", cov)).to eq(0)
      expect(stdout.string).to include("no coverable lines changed")
    end

    it "skips a file the change deletes" do
      init_repo
      write("lib/gone.rb", "a\nb\n")
      commit("base")
      git("checkout", "-q", "-b", "feature")
      File.delete(File.join(tmp, "lib/gone.rb"))
      commit("delete")
      write_report("lib/gone.rb", [1, 0], nil)

      expect(run_in_repo("patch", "--base", "main", "--input", cov)).to eq(0)
      expect(stdout.string).to include("no coverable lines changed")
    end

    it "drops a file whose touched lines are all never-relevant" do
      build_repo(base: "a\n", head: "a\n# note\n", line_hits: [1, nil])

      expect(run_in_repo("patch", "--base", "main", "--input", cov)).to eq(0)
      expect(stdout.string).to include("no coverable lines changed")
    end

    it "tolerates a coverage entry that isn't an object" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1], cover: false)
      File.write(cov, JSON.dump("coverage" => {File.join(tmp, "lib/foo.rb") => "malformed"}))

      expect(run_in_repo("patch", "--base", "main", "--input", cov)).to eq(0)
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
      # both touched lines are never-relevant (nil), but a branch sits on one
      build_repo(base: "a\n", head: "a\nif x\n  b\n", line_hits: [1, nil, nil],
                 branches: [{"report_line" => 2, "coverage" => 1}])

      run_in_repo("patch", "--base", "main", "--input", cov)
      expect(stdout.string).to match(%r{100\.00%\s+\(0/0\)\s+lines})
    end

    it "does not misread an added '++ ...' line as a file header" do
      # under --unified=0 an added line whose text starts with '++ '
      # renders as '+++ ...'; it must not redirect the file's later hunks
      diff = "diff --git a/lib/real.rb b/lib/real.rb\n" \
             "--- a/lib/real.rb\n+++ b/lib/real.rb\n" \
             "@@ -1,0 +2 @@\n+++ b/evil.rb\n" \
             "@@ -7 +8 @@\n-old\n+CHANGED\n"
      expect(SimpleCov::CLI::Patch::ChangedLines.parse_diff(diff)).to eq("lib/real.rb" => [2, 8])
    end

    it "gates on the exact ratio at the boundary" do
      patch = SimpleCov::CLI::Patch::Output
      # 23/40 is exactly 57.5%, which float division renders as 57.4999…
      expect(patch.short?({covered: 23, relevant: 40}, 57.5)).to be(false)
      expect(patch.short?({covered: 22, relevant: 40}, 57.5)).to be(true)
      # 19_999/20_000 = 99.995% must not round up to clear --minimum 100
      expect(patch.short?({covered: 19_999, relevant: 20_000}, 100)).to be(true)
      expect(patch.short?({covered: 20_000, relevant: 20_000}, 100)).to be(false)
      # 161/250 is exactly 64.4%; `64.4 * 250` overshoots in binary float
      expect(patch.short?({covered: 161, relevant: 250}, 64.4)).to be(false)
      expect(patch.short?({covered: 160, relevant: 250}, 64.4)).to be(true)
    end

    it "refuses a --base that git would read as an option" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])

      expect(run_in_repo("patch", "--base", "--output=/tmp/x", "--input", cov)).to eq(1)
      expect(stderr.string).to include("could not run `git diff`")
    end

    it "passes --minimum when nothing coverable changed" do
      build_repo(base: "a\n", head: "a\n# note\n", line_hits: [1, nil])

      expect(run_in_repo("patch", "--base", "main", "--input", cov, "--minimum", "100")).to eq(0)
    end

    it "counts a rename as all-new without --find-renames" do
      init_repo
      write("lib/old.rb", "a\nb\n")
      commit("base")
      git("checkout", "-q", "-b", "feature")
      git("mv", "lib/old.rb", "lib/new.rb")
      write("lib/new.rb", "a\nb\nc\n")
      commit("rename")
      write_report("lib/new.rb", [1, 1, 0], nil)

      # --no-renames (the default) makes the move a fresh add: lines 1-3 all
      # count, where --find-renames would score only the edited line 3
      run_in_repo("patch", "--base", "main", "--input", cov)
      expect(stdout.string).to include("(2/3)").and include("missing 3")
    end

    it "errors on a stray positional argument" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])

      # a forgotten `--base` leaves the ref as a bare positional
      expect(run_in_repo("patch", "feature", "--input", cov)).to eq(1)
      expect(stderr.string).to include("unexpected argument").and include("feature")
    end

    it "scores uncommitted working-tree changes" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1, 0])
      write("lib/foo.rb", "a\nb\nc\n") # a third line, not yet committed

      run_in_repo("patch", "--base", "main", "--input", cov)
      # --merge-base includes the working tree, so line 3 is in scope
      expect(stdout.string).to include("(1/2)").and include("missing 3")
    end

    it "reports on a change whose diff carries non-UTF-8 bytes" do
      build_repo(base: "a\n", head: "a\ns = \"caf\xE9\"\n".b, line_hits: [1, 1])

      expect(run_in_repo("patch", "--base", "main", "--input", cov)).to eq(0)
      expect(stdout.string).to match(%r{Patch coverage:\s+100\.00%\s+\(1/1\)})
    end

    it "resolves changed paths exactly instead of by suffix" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 0], cover: false)
      # The report tracks only a fixture copy whose key merely ends with
      # the changed path; a suffix match would score the fixture's hits
      # against lib/foo.rb's line numbers.
      write_coverage(File.join(tmp, "spec/fixtures/lib/foo.rb") => [0, 0])

      expect(run_in_repo("patch", "--base", "main", "--input", cov)).to eq(0)
      expect(stdout.string).to include("no coverable lines changed")
    end

    it "warns when a changed line lies beyond the report's lines" do
      build_repo(base: "a\n", head: "a\nb\nc\n", line_hits: [1])

      expect(run_in_repo("patch", "--base", "main", "--input", cov)).to eq(0)
      expect(stderr.string).to include("lib/foo.rb").and include("stale")
    end

    it "scores a brand-new untracked file before it is ever added" do
      init_repo
      write("lib/base.rb", "a\n")
      commit("base")
      write("lib/brand_new.rb", "a\nb\n") # never `git add`ed
      write_report("lib/brand_new.rb", [1, 0], nil)

      expect(run_in_repo("patch", "--base", "main", "--input", cov)).to eq(0)
      expect(stdout.string).to include("lib/brand_new.rb").and include("(1/2)").and include("missing 2")
    end

    # An ignored file is untracked on purpose. Scoring it would fail the
    # gate over generated output nobody wrote.
    # `git ls-files` hands back raw bytes, and a filename on disk need not
    # be valid UTF-8. Splitting on the NUL separator raises on such a
    # string, which would take the whole patch run down over a filename.
    it "scrubs bytes from git that are not valid UTF-8" do
      allow(SimpleCov::CLI::Git)
        .to receive(:capture)
        .and_return([(+"lib/ca\xFFe.rb\0lib/ok.rb\0").force_encoding(Encoding::UTF_8), "", true])

      expect(SimpleCov::CLI::Patch::ChangedLines.send(:untracked_files, "/anywhere"))
        .to eq(["lib/ca\uFFFDe.rb", "lib/ok.rb"])
    end

    it "leaves an ignored file out of the untracked ones" do
      init_repo
      write("lib/base.rb", "a\n")
      write(".gitignore", "lib/generated.rb\n")
      commit("base")
      write("lib/generated.rb", "a\n") # untracked, but ignored
      write_report("lib/generated.rb", [0], nil)

      expect(run_in_repo("patch", "--base", "main", "--input", cov, "--minimum", "100")).to eq(0)
      expect(stdout.string).not_to include("lib/generated.rb")
    end

    it "fails --minimum on an uncovered untracked file" do
      init_repo
      write("lib/base.rb", "a\n")
      commit("base")
      write("lib/brand_new.rb", "a\n")
      write_report("lib/brand_new.rb", [0], nil)

      expect(run_in_repo("patch", "--base", "main", "--input", cov, "--minimum", "100")).to eq(1)
    end

    it "relays git's own words when the base ref cannot be resolved" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 0])

      expect(run_in_repo("patch", "--base", "does-not-exist", "--input", cov)).to eq(1)
      expect(stderr.string).to match(/bad revision|unknown revision/)
    end

    it "scores a path git C-quotes" do
      skip "a quote is not a legal filename character on Windows" if Gem.win_platform?

      file = 'lib/we"ird.rb'
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 0], file: file)

      expect(run_in_repo("patch", "--base", "main", "--input", cov)).to eq(0)
      expect(stdout.string).to include(file).and include("missing 2")
    end

    it "reads an untracked file with a lineless report entry as nothing to cover" do
      init_repo
      write("lib/base.rb", "a\n")
      commit("base")
      write("lib/brand_new.rb", "a\n")
      write_coverage(File.join(tmp, "lib/brand_new.rb") => {})

      expect(run_in_repo("patch", "--base", "main", "--input", cov)).to eq(0)
      expect(stdout.string).to include("no coverable lines changed")
      expect(stderr.string).to be_empty
    end

    it "scores only branches for an entry that carries no lines array" do
      build_repo(base: "a\n", head: "a\nif x\n", line_hits: [], cover: false)
      write_coverage(File.join(tmp, "lib/foo.rb") => {"branches" => [{"report_line" => 2, "coverage" => 1}]})

      expect(run_in_repo("patch", "--base", "main", "--input", cov)).to eq(0)
      expect(stdout.string).to match(%r{100\.00%\s+\(0/0\)\s+lines}).and match(%r{100\.00%\s+\(1/1\)\s+branches})
    end

    it "errors outside a git working tree" do
      write_coverage(File.join(tmp, "lib/foo.rb") => [1])

      expect(run_in_repo("patch", "--base", "main", "--input", cov)).to eq(1)
      expect(stderr.string).to include("could not run `git diff`").and include("git working tree")
    end

    it "reports a git failure during the diff itself" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])
      allow(Open3).to receive(:capture3).and_call_original
      allow(Open3).to receive(:capture3)
        .with("git", "-C", anything, "-c", any_args).and_raise(Errno::EIO, "lost the disk")

      expect(run_in_repo("patch", "--base", "main", "--input", cov)).to eq(1)
      expect(stderr.string).to include("could not run `git diff`").and include("lost the disk")
    end

    it "keeps scoring the diff when the untracked listing fails" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])
      failed = instance_double(Process::Status, success?: false)
      allow(Open3).to receive(:capture3).and_call_original
      allow(Open3).to receive(:capture3)
        .with("git", "-C", anything, "ls-files", any_args).and_return(["", "", failed])

      expect(run_in_repo("patch", "--base", "main", "--input", cov)).to eq(0)
      expect(stdout.string).to match(%r{Patch coverage:\s+100\.00%\s+\(1/1\)})
    end

    it "keeps scoring the diff when the untracked listing raises" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])
      allow(Open3).to receive(:capture3).and_call_original
      allow(Open3).to receive(:capture3)
        .with("git", "-C", anything, "ls-files", any_args).and_raise(Errno::EIO, "lost the disk")

      expect(run_in_repo("patch", "--base", "main", "--input", cov)).to eq(0)
      expect(stdout.string).to match(%r{Patch coverage:\s+100\.00%\s+\(1/1\)})
    end

    # The diff is pinned against a user's git config so it cannot skew
    # the numbers, run code, or throw off the parse. Each of these
    # configures the repository the way a real one might be configured
    # and checks the score is the same.
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

          expect(run_in_repo("patch", "--base", "main", "--input", cov)).to eq(0)
          expect(stdout.string).to match(%r{Patch coverage:\s+50\.00%\s+\(1/2\)})
        end
      end

      # Two changes a few lines apart are two hunks, and merging them
      # would score the untouched lines between as this change's work.
      it "keeps hunks apart that a merged context would join" do
        git("checkout", "-q", "main")
        write("lib/foo.rb", "a\nb\nc\nd\ne\n")
        commit("five lines")
        git("checkout", "-q", "-B", "feature")
        write("lib/foo.rb", "A\nb\nc\nd\nE\n")
        commit("both ends")
        write_report("lib/foo.rb", [1, 0, 0, 0, 1], nil)
        git("config", "diff.interHunkContext", "5")

        expect(run_in_repo("patch", "--base", "main", "--input", cov)).to eq(0)
        expect(stdout.string).to match(%r{Patch coverage:\s+100\.00%\s+\(2/2\)})
      end

      # An external diff driver, or a textconv filter, replaces what git
      # prints with whatever a configured command says — including
      # nothing a hunk parser can read.
      it "scores the same change with an external diff driver configured" do
        git("config", "diff.external", "true")

        expect(run_in_repo("patch", "--base", "main", "--input", cov)).to eq(0)
        expect(stdout.string).to match(%r{Patch coverage:\s+50\.00%\s+\(1/2\)})
      end

      # A textconv filter that answers with fewer lines than the file has
      # would renumber every hunk after it.
      it "scores the same change with a textconv filter configured" do
        git("config", "diff.firstline.textconv", "head -1")
        write(".gitattributes", "*.rb diff=firstline\n")
        commit("textconv")

        expect(run_in_repo("patch", "--base", "main", "--input", cov)).to eq(0)
        expect(stdout.string).to match(%r{Patch coverage:\s+50\.00%\s+\(1/2\)})
      end

      # The merge base, not the branch tip: a base that has moved on
      # independently must not read as this change's work.
      it "scores against the merge base rather than the base's tip" do
        git("checkout", "-q", "main")
        write("lib/other.rb", "x\ny\n")
        commit("moved on")
        git("checkout", "-q", "feature")
        write_report("lib/foo.rb", [1, 1, 0], nil)

        expect(run_in_repo("patch", "--base", "main", "--input", cov)).to eq(0)
        expect(stdout.string).to match(%r{Patch coverage:\s+50\.00%\s+\(1/2\)})
      end
    end

    # A ref that begins with a dash is an option to git, not a
    # revision: `--output=FILE` writes to disk and `--line-prefix=`
    # empties the diff so a `--minimum` gate passes over the change.
    it "refuses a base that git would read as an option" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])

      expect(run_in_repo("patch", "--base", "--output=/tmp/pwned", "--input", cov)).to eq(1)
      expect(stderr.string)
        .to eq(%(simplecov patch: could not run `git diff` against "--output=/tmp/pwned" ) +
               %((a ref cannot begin with "-")\n))
    end

    # Outside a working tree there is nothing to diff, and the failure
    # is reported once rather than again on the way out.
    it "reports a missing working tree once, naming the base" do
      File.write(cov, JSON.dump("coverage" => {}))
      plain = Dir.mktmpdir("simplecov-cli-patch-nogit-")

      expect(Dir.chdir(plain) { run("patch", "--base", "main", "--input", cov) }).to eq(1)
      expect(stderr.string).to eq(%(simplecov patch: could not run `git diff` against "main" ) +
                                 %((is this a git working tree, and does the ref exist?)\n))
    ensure
      FileUtils.remove_entry(plain)
    end

    it "names the subcommand when the report cannot be read" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])

      expect(run_in_repo("patch", "--base", "main", "--input", "/no/such.json")).to eq(1)
      expect(stderr.string).to start_with("simplecov patch: ")
    end

    it "names the stray positional, and what to write instead" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])

      expect(run_in_repo("patch", "feature-x", "other", "--input", cov)).to eq(1)
      expect(stderr.string)
        .to eq(%(simplecov patch: unexpected argument "feature-x" (did you mean `--base feature-x`?)\n))
    end

    # `--base` left out falls back to the repository's own default
    # branch rather than to nothing.
    it "falls back to the repository's default branch" do
      build_repo(base: "a\n", head: "a\nb\nc\n", line_hits: [1, 1, 0])

      expect(run_in_repo("patch", "--input", cov)).to eq(0)
      expect(stdout.string).to match(%r{Patch coverage:\s+50\.00%\s+\(1/2\)})
    end

    # A minimum is a number, not the string it arrived as: compared as
    # text, "9" would sit above "50".
    it "takes a fractional minimum" do
      build_repo(base: "a\n", head: "a\nb\nc\n", line_hits: [1, 1, 0])

      expect(run_in_repo("patch", "--base", "main", "--input", cov, "--minimum", "50.5")).to eq(1)
      expect(run_in_repo("patch", "--base", "main", "--input", cov, "--minimum", "49.5")).to eq(0)
    end

    it "refuses a minimum that is not a number" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])

      expect(run_in_repo("patch", "--base", "main", "--input", cov, "--minimum", "lots")).to eq(1)
      expect(stderr.string).to include("invalid argument")
    end

    # The merge base, not the base's tip: work the base has done since
    # the branch point is not this change's work, and a plain diff would
    # read the base's own deletions as this change adding them back.
    it "scores against the merge base, not against the base's tip" do
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

      expect(run_in_repo("patch", "--base", "main", "--input", cov)).to eq(0)
      expect(stdout.string).to match(%r{Patch coverage:\s+0\.00%\s+\(0/1\)})
    end

    # Without the end-of-options marker, a ref that is also a filename
    # is ambiguous and git refuses to diff at all.
    it "diffs a ref that shares its name with a file" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])
      write("main", "a file named like the branch\n")
      commit("ambiguous")
      write_report("lib/foo.rb", [1, 1], nil)

      expect(run_in_repo("patch", "--base", "main", "--input", cov)).to eq(0)
      expect(stdout.string).to match(%r{Patch coverage:\s+100\.00%\s+\(1/1\)})
    end

    # A moved file reads as all-new unless renames are asked for, which
    # is what keeps a move from scoring as one changed line.
    it "scores a moved file as all-new unless it is asked to find renames" do
      init_repo
      write("lib/foo.rb", "a\nb\nc\n")
      commit("base")
      git("checkout", "-q", "-b", "feature")
      git("mv", "lib/foo.rb", "lib/bar.rb")
      write("lib/bar.rb", "a\nb\nd\n")
      commit("head")
      write_report("lib/bar.rb", [1, 1, 0], nil)

      expect(run_in_repo("patch", "--base", "main", "--input", cov)).to eq(0)
      expect(stdout.string).to match(%r{Patch coverage:\s+66\.67%\s+\(2/3\)})

      stdout.truncate(0) && stdout.rewind
      expect(run_in_repo("patch", "--base", "main", "--input", cov, "--find-renames")).to eq(0)
      expect(stdout.string).to match(%r{Patch coverage:\s+0\.00%\s+\(0/1\)})
    end

    # Branch and method misses are counted the same way lines are, and
    # two arms of one branch sit on the same line.
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

      it "counts nothing for entries that are not a list" do
        expect(entry_stats(nil, [1])).to be_nil
        expect(entry_stats(7, [1])).to be_nil
      end
    end

    # The missing lines are what the report prints, so they come out in
    # order however the hunks arrived, and a line the report says
    # nothing countable about is not a missing line.
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

      it "counts nothing at all for an entry with no line list" do
        expect(line_stats(nil, [1, 2])).to eq(covered: 0, relevant: 0, missing: [])
        expect(line_stats("junk", [1, 2])).to eq(covered: 0, relevant: 0, missing: [])
        expect(line_stats(7, [1, 2])).to eq(covered: 0, relevant: 0, missing: [])
      end
    end

    # The report may key a file by its absolute path or by the path the
    # diff names, and a file the report does not carry at all is simply
    # out of scope.
    describe "matching a changed file to its report entry" do
      def rows(coverage, changes, root: "/repo")
        SimpleCov::CLI::Patch.send(:compute_rows, coverage, {root: root, changes: changes}, StringIO.new)
      end

      it "finds an entry keyed the way the diff names the file" do
        found = rows({"lib/a.rb" => {"lines" => [1, 0]}}, {"lib/a.rb" => [1, 2]})

        expect(found.map { |row| row[:file] }).to eq(["lib/a.rb"])
      end

      # Expanded, so the key carries the drive letter the matcher's own
      # expansion gains on Windows.
      it "finds an entry keyed by its absolute path" do
        found = rows({File.expand_path("/repo/lib/a.rb") => {"lines" => [1, 0]}}, {"lib/a.rb" => [1, 2]})

        expect(found.map { |row| row[:file] }).to eq(["lib/a.rb"])
      end

      it "passes over a file the report does not carry" do
        expect(rows({"lib/other.rb" => {"lines" => [1]}}, {"lib/a.rb" => [1]})).to eq([])
      end

      it "passes over an entry that is not an object" do
        expect(rows({"lib/a.rb" => "junk"}, {"lib/a.rb" => [1]})).to eq([])
        expect(rows({"lib/a.rb" => 7}, {"lib/a.rb" => [1]})).to eq([])
      end
    end

    # A hunk header carries where the new side starts and how many
    # lines it runs for; a pure deletion runs for none.
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

      # An added line whose own text begins with "++ " renders as a
      # "+++" line inside the hunk, and only the section's first one is
      # the header.
      it "reads the section's own header, not a line that looks like one" do
        diff = "diff --git a/lib/a.rb b/lib/a.rb\n+++ b/lib/a.rb\n@@ -1,0 +2 @@\n+++ not/a/header.rb\n"

        expect(parse_diff(diff)).to eq("lib/a.rb" => [2])
      end

      it "passes over a section for a file that is only deleted" do
        diff = "diff --git a/lib/a.rb b/lib/a.rb\n+++ /dev/null\n@@ -1,2 +0,0 @@\n-a\n-b\n"

        expect(parse_diff(diff)).to eq({})
      end

      # The sections after a skipped one are still this change's work.
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

    # An untracked file is in no diff at all, so every line the report
    # knows about is this change's work, counted once.
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

      it "takes no lines from an untracked file the report says nothing about" do
        expect(changed_for(:all, {"lines" => nil})).to eq([])
        expect(changed_for(:all, {})).to eq([])
        expect(changed_for(:all, {"lines" => "junk"})).to eq([])
        expect(changed_for(:all, {"lines" => 7})).to eq([])
      end
    end

    # Branch and method entries come out of a report that may have been
    # written by an older SimpleCov, or hand-edited, so each entry is
    # taken only when it carries what it is read for.
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

    # A report written before the change it is being scored against
    # cannot say anything about the new lines, and saying so is more
    # useful than scoring them as uncovered.
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

      it "stays quiet about a line list that is not a list" do
        expect(warn_stale({"lines" => "junk"}, [1, 3])).to be_empty
        expect(warn_stale({"lines" => 7}, [1, 3])).to be_empty
      end

      it "stays quiet when nothing changed" do
        expect(warn_stale({"lines" => [1, 1]}, [])).to be_empty
      end

      it "stays quiet about an entry that carries no line list" do
        expect(warn_stale({"lines" => nil}, [1, 3])).to be_empty
        expect(warn_stale({"lines" => "junk"}, [1, 3])).to be_empty
      end

      # The furthest changed line decides, not the first or the nearest.
      it "warns on the furthest changed line, wherever it sits in the list" do
        expect(warn_stale({"lines" => [1, 1]}, [3, 1])).to include("changed beyond")
      end
    end

    # A row is worth showing when the change touched something that could
    # be measured: a coverable line, a branch, or a method.
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

      it "counts out a row that touched nothing measurable" do
        expect(scored?(0)).to be false
        expect(scored?(0, branch: {relevant: 0, covered: 0}, method: {relevant: 0, covered: 0})).to be false
      end
    end

    # The `+++` header names the file a hunk belongs to, and its own
    # shape is what the parser reads: a prefix git was told to emit, a
    # trailing newline, and git's literal token for a side that is not
    # there.
    describe "reading a diff header's path" do
      subject(:diff_path) { SimpleCov::CLI::Patch::ChangedLines.method(:diff_path) }

      it "strips the prefix git was told to emit" do
        expect(diff_path.call("+++ b/lib/foo.rb\n")).to eq("lib/foo.rb")
        expect(diff_path.call("--- a/lib/foo.rb\n")).to eq("lib/foo.rb")
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

    # git C-quotes a path carrying a quote, a backslash, or a control
    # character, even under core.quotePath=false, and a path left quoted
    # matches no coverage key at all.
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

      # Only a path quoted at both ends is a quoted path; anything else
      # is a path that happens to carry a quote.
      ["b/plain.rb", %("b/half.rb), %(b/half.rb"), %("), ""].each do |raw|
        it "leaves #{raw.inspect} exactly as it is" do
          expect(unquote.call(raw)).to eq(raw)
        end
      end

      # A path can carry a character git left alone beside a byte it
      # escaped, and a raw byte cannot be substituted into a string that
      # is already holding multibyte characters. Unescaped as bytes
      # throughout, the two live together and the unreadable one is
      # replaced at the end.
      it "reads a path that mixes a real character with an escaped byte" do
        expect(unquote.call(%("b/\u00e9\\377.rb"))).to eq("b/\u00e9\uFFFD.rb")
      end

      # An octal escape is a byte, not a character: mixing one into a
      # UTF-8 string mid-substitution is what the byte-wise pass avoids.
      it "keeps a path whose bytes are not UTF-8 readable" do
        expect(unquote.call(%("b/latin\\351.rb")).encoding).to eq(Encoding::UTF_8)
        expect(unquote.call(%("b/latin\\351.rb"))).to eq("b/latin\uFFFD.rb")
      end
    end

    it "scores changes outside the current subdirectory" do
      init_repo
      write("lib/foo.rb", "a\n")
      write("app/bar.rb", "a\n")
      commit("base")
      git("checkout", "-q", "-b", "feature")
      write("lib/foo.rb", "a\nb\n")
      write("app/bar.rb", "a\nb\n")
      commit("head")
      write_coverage(File.join(tmp, "lib/foo.rb") => [1, 1], File.join(tmp, "app/bar.rb") => [1, 0])

      Dir.chdir(File.join(tmp, "lib")) { expect(run("patch", "--base", "main", "--input", cov)).to eq(0) }
      expect(stdout.string).to include("lib/foo.rb").and include("app/bar.rb")
    end
  end

  describe "serve subcommand", mutant_expression: "SimpleCov::CLI::Serve*" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-serve-spec-") }
    # A socket's worth of surface: request bytes in, response bytes out.
    # The mechanics below answer the same whether the other end is a
    # browser or this.
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
      expect(run("serve")).to eq(1)
      expect(stderr.string).to include("doesn't exist")
    end

    it "errors before binding when the coverage dir has no report artifacts" do
      FileUtils.mkdir_p(tmp)
      allow(described_class).to receive(:coverage_dir).and_return(tmp)
      allow(TCPServer).to receive(:new).and_call_original

      expect(run("serve")).to eq(1)
      expect(stderr.string).to include("no index.html or coverage.json")
      expect(TCPServer).not_to have_received(:new)
    end

    it "errors cleanly when the port is already taken" do
      FileUtils.mkdir_p(tmp)
      File.write(File.join(tmp, "index.html"), "report")
      allow(described_class).to receive(:coverage_dir).and_return(tmp)

      blocker = TCPServer.new("127.0.0.1", 0)
      port = blocker.addr[1]

      begin
        expect(run("serve", "--port", port.to_s)).to eq(1)
        expect(stderr.string).to include("simplecov serve: cannot bind to 127.0.0.1:#{port}")
      ensure
        blocker.close
      end
    end

    it "serves an existing index without inspecting coverage.json" do
      FileUtils.mkdir_p(tmp)
      File.write(File.join(tmp, "index.html"), "existing report")
      File.write(File.join(tmp, "coverage.json"), "{")
      allow(described_class).to receive(:coverage_dir).and_return(tmp)
      allow(described_class::Serve).to receive(:with_server).and_return(0)

      expect(run("serve")).to eq(0)
      expect(File.read(File.join(tmp, "index.html"))).to eq("existing report")
      expect(described_class::Serve).to have_received(:with_server)
    end

    it "builds a missing index from coverage.json before binding" do
      FileUtils.mkdir_p(tmp)
      lines = {"covered" => 1, "missed" => 0, "total" => 1, "percent" => 100.0, "strength" => 1.0}
      data = {
        "meta" => {
          "simplecov_version" => SimpleCov::VERSION, "command_name" => "RSpec", "project_name" => "Example",
          "timestamp" => Time.now.iso8601, "line_coverage" => true,
          "branch_coverage" => false, "method_coverage" => false
        },
        "total" => {"lines" => lines},
        "coverage" => {"lib/a.rb" => {"source" => ["puts :ok"]}},
        "groups" => {}
      }
      File.write(File.join(tmp, "coverage.json"), JSON.dump(data))
      allow(described_class).to receive(:coverage_dir).and_return(tmp)
      allow(described_class::Serve).to receive(:with_server).and_return(0)

      expect(run("serve")).to eq(0)
      expect(File.read(File.join(tmp, "index.html"))).to include("window.SIMPLECOV_DATA")
      expect(described_class::Serve).to have_received(:with_server)
    end

    it "requires the stdlib sockets on the way in" do
      allow(described_class::Serve).to receive(:require)

      described_class::Serve.send(:require_socket)

      expect(described_class::Serve).to have_received(:require).with("socket")
    end

    # Preparing answers nothing when there is nothing to say, which is
    # what tells the run to go ahead and bind.
    describe "preparing the report" do
      let(:preparer) { described_class::Serve::ReportPreparer }

      it "loads the HTML formatter and hands the JSON to it, reporting nothing" do
        formatter = instance_double(SimpleCov::Formatter::HTMLFormatter)
        allow(preparer).to receive(:require_relative)
        allow(SimpleCov::Formatter::HTMLFormatter).to receive(:new).and_return(formatter)
        allow(formatter).to receive(:format_from_json).and_return("report")

        expect(preparer.send(:build_index, "cov/coverage.json", "cov")).to be_nil

        expect(preparer).to have_received(:require_relative).with("../../formatter/html_formatter")
        expect(formatter).to have_received(:format_from_json).with("cov/coverage.json", "cov")
      end

      it "answers nothing when the index is already there" do
        FileUtils.mkdir_p(tmp)
        File.write(File.join(tmp, "index.html"), "existing")

        expect(preparer.call(tmp)).to be_nil
      end

      it "answers nothing once it has built the index itself" do
        FileUtils.mkdir_p(tmp)
        File.write(File.join(tmp, "coverage.json"), JSON.dump(viewer_document))

        expect(preparer.call(tmp)).to be_nil
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

    it "reports invalid coverage.json before binding" do
      FileUtils.mkdir_p(tmp)
      json_path = File.join(tmp, "coverage.json")
      File.write(json_path, "{")
      allow(described_class).to receive(:coverage_dir).and_return(tmp)
      allow(TCPServer).to receive(:new).and_call_original

      expect(run("serve")).to eq(1)
      expect(stderr.string).to start_with("simplecov serve:")
      expect(stderr.string).to include("cannot build index.html").and include(json_path)
      expect(stderr.string.lines.size).to eq(1)
      expect(File).not_to exist(File.join(tmp, "index.html"))
      expect(TCPServer).not_to have_received(:new)
    end

    # The engines without IO#timeout= are the same, minus that method.
    def fake_client(request = "", timeout: true)
      klass = timeout ? fake_client_class : Class.new(fake_client_class) { undef_method(:timeout=) }
      klass.new(request)
    end

    # The accept loop runs until the terminal interrupts it, and says so
    # on the way out rather than leaving a bare ^C on the line.
    describe "the accept loop" do
      it "says it is stopping when it is interrupted" do
        server = instance_double(TCPServer)
        allow(server).to receive(:accept).and_raise(Interrupt)
        out = StringIO.new

        described_class::Serve.send(:serve_loop, server, tmp, out)

        expect(out.string).to eq("\nsimplecov serve: stopping\n")
      end

      # One thread per connection, so the assertions wait for them
      # rather than racing the loop's own exit.
      it "hands each accepted connection to the handler" do
        server = instance_double(TCPServer)
        accepted = %i[first second]
        allow(server).to receive(:accept) { accepted.shift or raise Interrupt }
        served = Queue.new
        allow(described_class::Serve::StaticFileHandler)
          .to receive(:handle_connection) { |client, dir| served << [client, dir] }

        described_class::Serve.send(:serve_loop, server, tmp, StringIO.new)

        expect([served.pop, served.pop]).to contain_exactly([:first, tmp], [:second, tmp])
      end
    end

    # A port already taken, a privileged port, or a host that resolves
    # nowhere: the reason git gives is the reason a user needs.
    describe "binding the socket" do
      it "reports the host, the port, and what the system said" do
        allow(TCPServer).to receive(:new).and_raise(Errno::EADDRINUSE)
        err = StringIO.new

        status = described_class::Serve.send(:with_server, {host: "127.0.0.1", port: 8080}, err) { 0 }

        expect(status).to eq(1)
        expect(err.string).to eq("simplecov serve: cannot bind to 127.0.0.1:8080 " \
                                 "(#{Errno::EADDRINUSE.new.message})\n")
      end

      it "closes the server when the block is done with it" do
        server = instance_double(TCPServer, close: nil)
        allow(TCPServer).to receive(:new).and_return(server)

        expect(described_class::Serve.send(:with_server, {host: "::1", port: 0}, StringIO.new) { 7 }).to eq(7)
        expect(server).to have_received(:close)
      end
    end

    # The announcement is the only way anyone learns which port the
    # server took when it was asked for any port at all.
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

      # An IPv6 literal needs brackets, or the port reads as part of the
      # address.
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

      # JRuby and TruffleRuby have no IO#timeout=, and a connection
      # there is served without one rather than failing.
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

      # A route takes over the connection, and what it reads next is the
      # body rather than the rest of the headers.
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

      # A client that hangs up mid-request is the ordinary case, not a
      # reason to take the server down.
      it "closes quietly on a request that stops early" do
        client = fake_client("GET /index.html HTTP/1.1\r\n")

        expect { handler.handle_connection(client, tmp) }.not_to raise_error
        expect(client.closed).to be true
      end
    end

    # Headers are read to the blank line and no further: what follows is
    # the body, and a route may want it.
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

      it "names the status it is answering with" do
        expect(respond(200)).to start_with("HTTP/1.1 200 OK\r\n")
        expect(respond(400)).to start_with("HTTP/1.1 400 Bad Request\r\n")
        expect(respond(403)).to start_with("HTTP/1.1 403 Forbidden\r\n")
        expect(respond(404)).to start_with("HTTP/1.1 404 Not Found\r\n")
        expect(respond(405)).to start_with("HTTP/1.1 405 Method Not Allowed\r\n")
      end

      it "answers a status it has no name for with one anyway" do
        expect(respond(418)).to start_with("HTTP/1.1 418 Error\r\n")
      end

      it "says the body is text unless told otherwise" do
        expect(respond(404)).to include("Content-Type: text/plain\r\n")
        expect(respond(200, "body", "text/css")).to include("Content-Type: text/css\r\n")
      end

      # A file whose extension nothing recognises is bytes, and saying
      # so is what keeps a browser from guessing.
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

      it "answers a missing file with not-found, and a traversal with forbidden" do
        expect(serve("/missing.html")).to start_with("HTTP/1.1 404")
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

      it "answers anything but a GET with method-not-allowed, once" do
        %w[POST HEAD PUT].each do |method|
          answer = dispatch(method, "/")

          expect(answer).to start_with("HTTP/1.1 405")
          expect(answer.scan("HTTP/1.1").size).to eq(1)
        end
      end

      it "hands a mounted path to its route, query string and all" do
        taken = []
        routes = {"/events" => ->(client) { taken << client }}

        expect(dispatch("GET", "/events?since=3", routes)).to eq("")
        expect(taken.size).to eq(1)
      end

      it "serves a file for a path nothing is mounted on" do
        expect(dispatch("GET", "/index.html", {"/events" => ->(_) {}})).to start_with("HTTP/1.1 200")
      end
    end

    # Root itself is inside root; a sibling whose name merely starts the
    # same way is not.
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

      # A directory with no index.html is nothing to serve, and asking
      # to read it would be an error rather than a 404.
      it "returns nil for a directory that carries no index" do
        FileUtils.mkdir_p(File.join(tmp, "empty"))

        expect(handler.resolve("/empty", tmp)).to be_nil
      end

      # A pipe in the report directory is not a file to read: reading
      # one would block the connection until something wrote to it.
      it "returns nil for something that is neither a file nor a directory" do
        skip "no mkfifo on this platform" unless File.respond_to?(:mkfifo)
        File.mkfifo(File.join(tmp, "pipe"))

        expect(handler.resolve("/pipe", tmp)).to be_nil
      end

      # The file can go between the check and the read; that is a race,
      # not a refusal.
      it "returns nil for a file that vanishes mid-resolve" do
        vanishing = File.join(File.realpath(tmp), "index.html")
        allow(File).to receive(:realpath).and_call_original
        allow(File).to receive(:realpath).with(vanishing).and_raise(Errno::ENOENT)

        expect(handler.resolve("/index.html", tmp)).to be_nil
      end

      it "returns nil for a missing file" do
        expect(handler.resolve("/missing.html", tmp)).to be_nil
      end

      # The root is resolved to its real path before the containment
      # checks, so a root handed over as a symlink still serves: without
      # that, every candidate's real path would fall outside the symlink
      # spelling of the root and read as traversal. Pinned with an
      # explicit symlink, because macOS hides one under every tmpdir
      # while Linux does not.
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
      FileUtils.mkdir_p(tmp)
      server = TCPServer.new("127.0.0.1", 0)
      thread = Thread.new { described_class::Serve::StaticFileHandler.handle_connection(server.accept, tmp) }
      sock = TCPSocket.new("127.0.0.1", server.addr[1])
      # Raw request so the path isn't normalized by Net::HTTP / URI.
      sock.write("GET /../secret.txt HTTP/1.1\r\nHost: x\r\n\r\n")
      expect(sock.read).to start_with("HTTP/1.1 403")
    ensure
      sock&.close
      thread&.join(2)
      server&.close
    end

    # The routes seam `simplecov watch` mounts its /events endpoint and
    # reload-injecting index route on.
    it "hands a matching path to its route instead of the file tree" do
      FileUtils.mkdir_p(tmp)
      File.write(File.join(tmp, "index.html"), "plain")
      handler = described_class::Serve::StaticFileHandler
      routes = {"/events" => ->(client) { handler.respond(client, 200, "routed") }}

      server = TCPServer.new("127.0.0.1", 0)
      thread = Thread.new { handler.handle_connection(server.accept, tmp, routes) }
      sock = TCPSocket.new("127.0.0.1", server.addr[1])
      sock.write("GET /events?tab=1 HTTP/1.1\r\nHost: x\r\n\r\n")
      expect(sock.read).to include("routed")
      thread.join(2)

      thread = Thread.new { handler.handle_connection(server.accept, tmp, routes) }
      sock = TCPSocket.new("127.0.0.1", server.addr[1])
      sock.write("GET /index.html HTTP/1.1\r\nHost: x\r\n\r\n")
      expect(sock.read).to include("plain")
    ensure
      sock&.close
      thread&.join(2)
      server&.close
    end

    # A malformed request line used to raise inside the wide rescue and
    # close the connection with an empty response; the 400 status text
    # was defined but unreachable.
    it "responds 400 to a malformed request line" do
      FileUtils.mkdir_p(tmp)
      server = TCPServer.new("127.0.0.1", 0)
      thread = Thread.new { described_class::Serve::StaticFileHandler.handle_connection(server.accept, tmp) }
      sock = TCPSocket.new("127.0.0.1", server.addr[1])
      sock.write("GET\r\n\r\n")
      expect(sock.read).to start_with("HTTP/1.1 400")
    ensure
      sock&.close
      thread&.join(2)
      server&.close
    end

    it "brackets IPv6 hosts in the announced URL" do
      expect(described_class::Serve.url_host("::1")).to eq("[::1]")
      expect(described_class::Serve.url_host("127.0.0.1")).to eq("127.0.0.1")
    end

    it "exits 405 for non-GET requests" do
      FileUtils.mkdir_p(tmp)
      server = TCPServer.new("127.0.0.1", 0)
      thread = Thread.new do
        described_class::Serve::StaticFileHandler.handle_connection(server.accept, tmp)
      end
      sock = TCPSocket.new("127.0.0.1", server.addr[1])
      sock.write("POST / HTTP/1.1\r\nHost: x\r\n\r\n")
      response = sock.read
      expect(response).to start_with("HTTP/1.1 405")
    ensure
      sock&.close
      thread&.join(2)
      server&.close
    end

    it "rescues a misbehaving client without crashing" do
      FileUtils.mkdir_p(tmp)
      server = TCPServer.new("127.0.0.1", 0)
      Thread.new do
        s = TCPSocket.new("127.0.0.1", server.addr[1])
        s.close
      end
      accepted = server.accept
      expect { described_class::Serve::StaticFileHandler.handle_connection(accepted, tmp) }.not_to raise_error
    ensure
      server&.close
    end

    it "closes a bound server when its block raises" do
      server = instance_double(TCPServer, close: nil)
      allow(TCPServer).to receive(:new).and_return(server)

      expect do
        described_class::Serve.with_server({host: "127.0.0.1", port: 0}, stderr) { raise "boom" }
      end.to raise_error(RuntimeError, "boom")
      expect(server).to have_received(:close)
    end

    # Watches for the announcement and hands back the URL it named,
    # letting the real one still print.
    def announcing_url
      announced = Queue.new
      original = described_class::Serve.method(:announce)
      allow(described_class::Serve).to receive(:announce) do |out, server, dir|
        announced << "http://#{server.addr[3]}:#{server.addr[1]}/"
        original.call(out, server, dir)
      end
      announced
    end

    # End-to-end through `run`: spin the full entry point in a thread,
    # hit it, then signal Ctrl-C to stop. Exercises `run`, `announce`,
    # the serve_loop exit path, and the ensure-time `server.close`.
    it "serves the report end-to-end through the run entry point" do
      File.write(File.join(tmp, "index.html"), "<html>via-run</html>")
      allow(described_class).to receive(:coverage_dir).and_return(tmp)

      announced = announcing_url
      allow(described_class::Serve).to receive(:require_socket).and_call_original

      thread = Thread.new { described_class.run(["serve"], stdout: stdout, stderr: stderr) }
      begin
        url = announced.pop
        response = Net::HTTP.get_response(URI(url))
        expect(response.code).to eq("200")
        expect(response.body).to include("via-run")
        not_found = Net::HTTP.get_response(URI("#{url}missing.html"))
        expect(not_found.code).to eq("404")
      ensure
        thread.raise(Interrupt) if thread.alive?
        status = thread.join(2)&.value
      end

      # The run answers success once it is stopped, having said where it
      # was listening and loaded the sockets it needed to.
      expect(status).to eq(0)
      expect(stdout.string).to include("simplecov serve: serving #{tmp} at http://")
      expect(described_class::Serve).to have_received(:require_socket)
    end

    # Browsers open speculative connections that send no bytes; each
    # connection gets its own thread so those can't stall real requests.
    it "answers a request while another connection sits idle" do
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
        idle = TCPSocket.new(uri.host, uri.port) # never sends a request
        response = Net::HTTP.get_response(uri)
        expect(response.code).to eq("200")
        expect(response.body).to include("concurrent")
      ensure
        idle&.close
        thread.raise(Interrupt) if thread.alive?
        thread.join(2)
      end
    end
  end

  describe "watch subcommand" do
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

    # A stand-in suite: logs its arguments and merge window, then
    # regenerates the report at a new percentage, like a real run would.
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

    def wait_for
      Timeout.timeout(10) do
        sleep(0.05) until yield
      end
    end

    # The fake suite's log line lands when the child's buffered write
    # flushes at close, after the file itself appears — waiting on bare
    # existence read an empty file on slow-starting engines (JRuby).
    def wait_for_log
      wait_for { File.exist?(log_path) && File.read(log_path).include?("window=") }
    end

    def touch_code
      FileUtils.mkdir_p(File.dirname(code_path))
      File.write(code_path, "# changed #{rand}\n")
      FileUtils.touch(code_path, mtime: Time.now + 2)
    end

    before do
      # Decoupled from the process-wide memoized discovery, like the
      # serve specs, so suite order can't hand watch a stale directory.
      allow(described_class).to receive(:coverage_dir).and_return(coverage_dir)
      FileUtils.mkdir_p(File.dirname(code_path))
      File.write(code_path, "# original\n")
      FileUtils.mkdir_p(File.join(tmp, "spec"))
      File.write(File.join(tmp, "spec/code_spec.rb"), "# spec\n")
    end

    it "reruns the recorded tests for a changed file and reloads the report" do
      write_report
      thread, port = start_watch(*fake_suite)
      begin
        events = TCPSocket.new("127.0.0.1", port)
        events.write("GET /events HTTP/1.1\r\nHost: x\r\n\r\n")
        wait_for { events.readline.strip.empty? } # drain response headers

        touch_code
        wait_for_log
        expect(File.read(log_path)).to include("args=spec/code_spec.rb window=86400")
        expect(Timeout.timeout(10) { events.readline }).to include("data: reload")
        wait_for { stdout.string.include?("lib/code.rb changed, running 1 file... 95.00% (+5.00%)") }
      ensure
        events&.close
        stop_watch(thread)
      end
      expect(stdout.string).to include("watching 2 files, serving http://127.0.0.1:#{port}/")
    end

    it "serves the report with the reload listener injected" do
      write_report
      thread, port = start_watch(*fake_suite)
      begin
        response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/"))
        expect(response.code).to eq("200")
        expect(response.body).to include("<html>report</html>").and include("EventSource('/events')")
        expect(File.read(File.join(coverage_dir, "index.html"))).to eq("<html>report</html>")
      ensure
        stop_watch(thread)
      end
    end

    it "runs the full command when the report carries no test map" do
      write_report(contexts: nil, tables: nil)
      thread, = start_watch(*fake_suite)
      begin
        touch_code
        wait_for_log
        expect(File.read(log_path)).to include("args= ")
        wait_for { stdout.string.include?("running the full suite") }
      ensure
        stop_watch(thread)
      end
    end

    it "notes a change no recorded test touches without running anything" do
      write_report(tables: {})
      thread, = start_watch(*fake_suite)
      begin
        touch_code
        wait_for { stdout.string.include?("no recorded test touches it") }
        expect(File.exist?(log_path)).to be(false)
      ensure
        stop_watch(thread)
      end
    end

    it "builds the initial report by running the command once when it is missing" do
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
      thread, = start_watch(*command)
      stop_watch(thread)
      expect(File.read(log_path)).to include("args= ")
      expect(stdout.string).to include("watching 1 file, serving")
    end

    it "reports the new percentage without a delta when the report had no baseline" do
      write_report(percent: nil, contexts: nil, tables: nil)
      thread, = start_watch(*fake_suite)
      begin
        touch_code
        wait_for { stdout.string.include?("running the full suite... 95.00%\n") }
        expect(stdout.string).not_to include("(+")
      ensure
        stop_watch(thread)
      end
    end

    it "ends the result line bare when the regenerated report has no totals" do
      write_report(contexts: nil, tables: nil)
      thread, = start_watch(*fake_suite(percent: nil))
      begin
        touch_code
        wait_for { stdout.string.include?("running the full suite...\n") }
        expect(stdout.string).not_to include("%\n")
      ensure
        stop_watch(thread)
      end
    end

    it "says so when the run leaves the report unreadable" do
      write_report(contexts: nil, tables: nil)
      breaker = File.join(tmp, "break.rb")
      File.write(breaker, "File.write(#{json_path.inspect}, '{')")
      thread, = start_watch(RbConfig.ruby, breaker)
      begin
        touch_code
        wait_for { stdout.string.include?("the report did not regenerate") }
        expect(stderr.string).to include("isn't valid JSON")
      ensure
        stop_watch(thread)
      end
    end

    it "reports the primary criterion's percent when the report names one" do
      session = described_class::Watch::Session.new(command: ["true"], dir: coverage_dir,
                                                    interval: 0.01, stdout: stdout, stderr: stderr)
      session.instance_variable_set(:@document, {
                                      "meta" => {"primary_coverage" => "branch"},
                                      "total" => {"lines" => {"percent" => 90.0}, "branches" => {"percent" => 75.0}}
                                    })
      expect(session.send(:total_percent)).to eq(75.0)
    end

    it "collects an editor's save burst into one run" do
      session = described_class::Watch::Session.new(command: ["true"], dir: coverage_dir,
                                                    interval: 0.01, stdout: stdout, stderr: stderr)
      scripted = Struct.new(:sequence) { def changes = sequence.shift || [] }
      session.instance_variable_set(:@poller, scripted.new([["a.rb"], ["b.rb"], []]))
      expect(session.send(:settled_changes)).to eq(["a.rb", "b.rb"])
    end

    it "errors without a command" do
      expect(run("watch")).to eq(1)
      expect(stderr.string).to include("missing command")
    end

    it "errors when the port is already taken" do
      write_report
      blocker = TCPServer.new("127.0.0.1", 0)
      begin
        expect(Dir.chdir(tmp) { run("watch", "--port", blocker.addr[1].to_s, "ruby", "-e", "1") }).to eq(1)
        expect(stderr.string).to include("simplecov watch: cannot bind")
      ensure
        blocker.close
      end
    end

    it "exits non-zero when the initial run produces no report" do
      expect(Dir.chdir(tmp) { run("watch", RbConfig.ruby, "-e", "0") }).to eq(1)
      expect(stderr.string).to include("not found")
    end

    it "leaves the runner's own flags alone" do
      opts, command = described_class::Watch.parse(["--interval", "1", "bundle", "exec", "rspec", "--seed", "1"])
      expect(opts[:interval]).to eq(1.0)
      expect(command).to eq(["bundle", "exec", "rspec", "--seed", "1"])
    end

    it "opens the served report in the browser under --open" do
      write_report
      opened = Queue.new
      allow(described_class::Watch).to receive(:launch_browser) { |server, _stderr| opened << server.addr[1] }
      thread, port = start_watch("--open", *fake_suite)
      begin
        expect(Timeout.timeout(10) { opened.pop }).to eq(port)
      ensure
        stop_watch(thread)
      end
    end

    it "hands the report URL to the platform opener" do
      server = instance_double(TCPServer, addr: ["AF_INET", 53_422, "localhost", "127.0.0.1"])
      allow(described_class::Open).to receive(:browser_opener).and_return(["fake-open"])
      allow(described_class::Watch).to receive(:spawn).and_return(4242)
      allow(Process).to receive(:detach)

      described_class::Watch.launch_browser(server, stderr)

      expect(described_class::Watch).to have_received(:spawn) do |*argv, **options|
        expect(argv).to eq(["fake-open", "http://127.0.0.1:53422/"])
        expect(options).to include(out: File::NULL, err: File::NULL)
      end
      expect(Process).to have_received(:detach).with(4242)
    end

    it "degrades to a note when the platform has no known opener" do
      server = instance_double(TCPServer, addr: ["AF_INET", 53_422, "localhost", "127.0.0.1"])
      allow(described_class::Open).to receive(:browser_opener).and_return(nil)
      allow(Process).to receive(:spawn)

      described_class::Watch.launch_browser(server, stderr)

      expect(Process).not_to have_received(:spawn)
      expect(stderr.string).to include("http://127.0.0.1:53422/").and include("open it yourself")
    end

    describe SimpleCov::CLI::Watch::Poller do
      let(:poller) { described_class.new }
      let(:file) { File.join(tmp, "a.rb") }

      it "reports nothing while mtimes hold still" do
        File.write(file, "a")
        poller.watch([file])
        expect(poller.changes).to eq([])
      end

      it "reports a touched file once per change" do
        File.write(file, "a")
        poller.watch([file])
        FileUtils.touch(file, mtime: Time.now + 2)
        expect(poller.changes).to eq([file])
        expect(poller.changes).to eq([])
      end

      it "reports a vanished file and an appearing one" do
        File.write(file, "a")
        poller.watch([file])
        File.delete(file)
        expect(poller.changes).to eq([file])
        File.write(file, "b")
        expect(poller.changes).to eq([file])
      end
    end

    describe SimpleCov::CLI::Watch::Narrator do
      it "names a burst by its first file and counts the rest" do
        narrator = described_class.new(stdout, "/root")
        narrator.change(["/root/a.rb", "/root/b.rb"], {run: true, tests: ["spec/a_spec.rb", "spec/b_spec.rb"]})
        expect(stdout.string).to eq("a.rb and 1 more changed, running 2 files...")
      end
    end

    describe SimpleCov::CLI::Watch::TestPlan do
      it "fails open to the full command on a selection trigger" do
        document = {
          "contexts" => ["spec/ghost_spec.rb:1"],
          "coverage" => {File.join(tmp, "lib/code.rb") => {"lines" => [1], "contexts" => {"0" => "1"}}}
        }
        plan = Dir.chdir(tmp) do
          described_class.build(["lib/code.rb"], document, root: tmp, input: "coverage.json", stderr: stderr)
        end
        expect(plan).to eq(run: true, tests: nil)
        expect(stderr.string).to be_empty
      end

      it "derives the watch set without a coverage section" do
        paths = described_class.watched_paths({"contexts" => ["spec/a_spec.rb:1"]}, tmp)
        expect(paths).to eq([File.join(tmp, "spec/a_spec.rb")])
      end
    end

    describe SimpleCov::CLI::Watch::LiveReport do
      it "drops a departed tab's queue after a failed write" do
        live = described_class.new(tmp)
        server = TCPServer.new("127.0.0.1", 0)
        client = TCPSocket.new("127.0.0.1", server.addr[1])
        served = server.accept
        thread = Thread.new { live.stream(served) }
        wait_for { live.instance_variable_get(:@queues).size == 1 }
        wait_for { client.readline.strip.empty? } # drain response headers
        served.close
        live.broadcast
        thread.join(5)
        expect(live.instance_variable_get(:@queues)).to be_empty
      ensure
        client&.close
        server&.close
      end

      it "answers 404 for the page before a report exists" do
        live = described_class.new(tmp)
        server = TCPServer.new("127.0.0.1", 0)
        thread = Thread.new do
          SimpleCov::CLI::Serve::StaticFileHandler.handle_connection(server.accept, tmp, live.routes)
        end
        sock = TCPSocket.new("127.0.0.1", server.addr[1])
        sock.write("GET / HTTP/1.1\r\nHost: x\r\n\r\n")
        expect(sock.read).to start_with("HTTP/1.1 404")
      ensure
        sock&.close
        thread&.join(2)
        server&.close
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

    it "protects the working directory by its canonical spelling" do
      allow(described_class::Clean).to receive(:canonical_path).and_return("/canonical/cwd")

      expect(described_class::Clean.send(:protected_paths)).to eq(["/canonical/cwd"])
      expect(described_class::Clean).to have_received(:canonical_path).with(Dir.pwd)
    end

    it "removes the coverage directory and reports what was deleted" do
      expect(run("clean")).to eq(0)
      expect(File).not_to exist(tmp)
      expect(stdout.string).to include("removed #{tmp}")
    end

    it "leaves disk untouched under --dry-run" do
      expect(run("clean", "--dry-run")).to eq(0)
      expect(File).to exist(tmp)
      expect(stdout.string).to include("would remove #{tmp}")
    end

    # The pre-fix Dir[] glob skipped dotfiles, so a typical coverage dir
    # holding .resultset.json undercounted what rm_rf would delete.
    it "counts dotfiles in the --dry-run entry count" do
      File.write(File.join(tmp, ".resultset.json"), "{}")

      expect(run("clean", "--dry-run")).to eq(0)
      # assets/, index.html, coverage.json, and .resultset.json
      expect(stdout.string).to include("(4 entries)")
    end

    it "is a no-op when the directory doesn't exist" do
      FileUtils.remove_entry(tmp)
      expect(run("clean")).to eq(0)
      # Whole line: the report has to name the directory, and reporting
      # it must be the end of the run rather than a preamble to a sweep.
      expect(stdout.string).to eq("simplecov clean: #{tmp} doesn't exist; nothing to do\n")
    end

    it "names the directory it removed, under the command's own name" do
      expect(run("clean")).to eq(0)
      expect(stdout.string).to eq("simplecov clean: removed #{tmp}\n")
    end

    it "quotes the directory it refuses, so a stray space is visible" do
      Dir.chdir(tmp) do
        allow(described_class).to receive(:coverage_dir).and_return(".")

        run("clean")
        expect(stderr.string).to eq(
          "simplecov clean: refusing to remove unsafe coverage directory \".\"\n"
        )
      end
    end

    # The guard compares against the working directory as a path, not as
    # a prefix: a sibling whose name merely starts the same way is not an
    # ancestor of anything and is free to be removed.
    it "removes a directory whose name prefixes the working directory's" do
      sibling = File.join(tmp, "coverage")
      nested  = File.join(tmp, "coverage-data")
      FileUtils.mkdir_p(sibling)
      FileUtils.mkdir_p(nested)

      Dir.chdir(nested) do
        allow(described_class).to receive(:coverage_dir).and_return(sibling)

        expect(run("clean")).to eq(0)
        expect(File).not_to exist(sibling)
      end
    end

    it "silences all status lines under --quiet" do
      expect(run("clean", "--quiet")).to eq(0)
      expect(File).not_to exist(tmp)
      expect(stdout.string).to be_empty
    end

    it "silences the --dry-run status line under --quiet" do
      expect(run("clean", "--dry-run", "--quiet")).to eq(0)
      expect(File).to exist(tmp)
      expect(stdout.string).to be_empty
    end

    it "silences the noop status line under --quiet" do
      FileUtils.remove_entry(tmp)
      expect(run("clean", "-q")).to eq(0)
      expect(stdout.string).to be_empty
    end

    it "refuses to remove the current directory" do
      Dir.chdir(tmp) do
        allow(described_class).to receive(:coverage_dir).and_return(".")

        expect(run("clean")).to eq(1)
        expect(File).to exist(File.join(tmp, "index.html"))
        expect(stderr.string).to include("refusing to remove unsafe coverage directory")
      end
    end

    it "refuses to remove an ancestor of the current directory" do
      child = File.join(tmp, "nested")
      FileUtils.mkdir_p(child)

      Dir.chdir(child) do
        allow(described_class).to receive(:coverage_dir).and_return("..")

        expect(run("clean", "--quiet")).to eq(1)
        expect(File).to exist(File.join(tmp, "index.html"))
        expect(stderr.string).to include("refusing to remove unsafe coverage directory")
      end
    end

    it "refuses to remove the filesystem root" do
      allow(described_class).to receive(:coverage_dir).and_return(File::SEPARATOR)

      # --dry-run as defense in depth: if the guard ever regresses, the
      # failure is a wrong message, not a recursive delete from the root
      # of the CI runner's disk.
      expect(run("clean", "--dry-run")).to eq(1)
      expect(stderr.string).to include("refusing to remove unsafe coverage directory")
    end

    it "refuses to remove the project root found through .simplecov" do
      File.write(File.join(tmp, ".simplecov"), "# project config\n")
      child = File.join(tmp, "nested")
      FileUtils.mkdir_p(child)

      Dir.chdir(child) do
        allow(described_class).to receive(:coverage_dir).and_return(tmp)

        expect(run("clean")).to eq(1)
        expect(File).to exist(File.join(tmp, "index.html"))
      end
    end
  end

  describe "open subcommand", mutant_expression: "SimpleCov::CLI::Open*" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-open-spec-") }

    after { FileUtils.remove_entry(tmp) }

    it "errors when the report file is missing, naming it" do
      missing = File.join(tmp, "missing.html")

      expect(run("open", "--report", missing)).to eq(1)
      expect(stderr.string).to eq("simplecov open: #{missing} not found\n")
    end

    # Without --report the report is the one the project writes.
    it "opens the project's own report when told of no other" do
      expect(SimpleCov::CLI::Open.parse([])).to eq(described_class.default_report)
    end

    it "shells out to the platform opener with the report path" do
      report = File.join(tmp, "index.html")
      File.write(report, "<html></html>")
      allow(SimpleCov::CLI::Open).to receive_messages(browser_opener: ["open"], system: true)

      expect(run("open", "--report", report)).to eq(0)
      expect(SimpleCov::CLI::Open).to have_received(:system).with("open", report)
    end

    it "errors when the platform has no known opener, naming the platform" do
      report = File.join(tmp, "index.html")
      File.write(report, "<html></html>")
      allow(SimpleCov::CLI::Open).to receive(:browser_opener).and_return(nil)
      stub_const("RbConfig::CONFIG", RbConfig::CONFIG.merge("host_os" => "exotic-os"))

      expect(run("open", "--report", report)).to eq(1)
      expect(stderr.string).to eq("simplecov open: no known opener for exotic-os\n")
    end

    it "returns 1 when the opener exits non-zero" do
      report = File.join(tmp, "index.html")
      File.write(report, "<html></html>")
      allow(SimpleCov::CLI::Open).to receive_messages(browser_opener: ["open"], system: false)

      expect(run("open", "--report", report)).to eq(1)
    end

    it "routes through `cmd /c start` on Windows so cmd builtins resolve" do
      report = File.join(tmp, "index.html")
      File.write(report, "<html></html>")
      stub_const("RbConfig::CONFIG", RbConfig::CONFIG.merge("host_os" => "mswin64"))
      allow(SimpleCov::CLI::Open).to receive(:system).and_return(true)

      expect(run("open", "--report", report)).to eq(0)
      expect(SimpleCov::CLI::Open).to have_received(:system).with("cmd", "/c", "start", "", report)
    end

    describe ".browser_opener" do
      it "picks `open` on macOS" do
        stub_const("RbConfig::CONFIG", RbConfig::CONFIG.merge("host_os" => "darwin23"))
        expect(SimpleCov::CLI::Open.browser_opener).to eq(["open"])
      end

      # Every spelling of each family, since one of them standing in for
      # the others leaves the rest free to go unrecognized.
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

  # These have to shell out to the real `exe/simplecov`. The bug they
  # guard (SimpleCov.color undefined) only exists in a process that
  # loaded `simplecov/cli` *without* `simplecov` — the in-process specs
  # above always have the full library loaded via spec/helper, so they
  # can't see it. The reproduction also needs a directory with no
  # `.simplecov` above it, since finding one lazily requires the full
  # library and incidentally defines `SimpleCov.color`.
  describe "colorizing subcommands in the standalone CLI process", mutant: false do
    let(:exe) { File.expand_path("../exe/simplecov", __dir__) }
    let(:lib) { File.expand_path("../lib", __dir__) }
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

    # `coverage` needs a file path present in the JSON; `diff` needs a
    # baseline (the same coverage.json is a fine zero-delta baseline).
    {
      "report" => [],
      "uncovered" => [],
      "coverage" => ["/project/app.rb"],
      "diff" => ["coverage/coverage.json"]
    }.each do |subcommand, extra_args|
      it "runs `#{subcommand}` without SimpleCov.color being loaded" do
        _stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-I", lib, exe, subcommand, *extra_args)
        expect(stderr).not_to include("NoMethodError")
        expect(status).to be_success
      end
    end
  end
end
