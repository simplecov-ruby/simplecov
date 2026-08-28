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

  describe SimpleCov::CLI::Git do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-git-spec-") }

    after { FileUtils.rm_rf(tmp) }

    def repo!(branch)
      system("git", "-C", tmp, "init", "-q", "-b", branch, exception: true)
      system("git", "-C", tmp, "config", "maintenance.auto", "false", exception: true)
      system("git", "-C", tmp, "-c", "user.email=spec@example.com", "-c", "user.name=spec",
             "commit", "-q", "--allow-empty", "-m", "init", exception: true)
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

    describe ".capture" do
      it "reads a spawn failure as an unsuccessful run carrying the message" do
        allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT, "git")
        stdout, detail, success = described_class.capture("status")
        expect(stdout).to be_nil
        expect(detail).to include("git")
        expect(success).to be(false)
      end
    end

    describe ".option_like_ref?" do
      it "flags refs git would parse as options" do
        expect(described_class.option_like_ref?("--output=x")).to be(true)
        expect(described_class.option_like_ref?("main")).to be(false)
      end
    end
  end

  describe "status subcommand" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-status-spec-") }
    let(:json_path) { File.join(tmp, "coverage.json") }
    let(:resultset_path) { File.join(tmp, ".resultset.json") }

    before { allow(described_class).to receive(:default_resultset).and_return(resultset_path) }

    after { FileUtils.rm_rf(tmp) }

    def repo!
      system("git", "-C", tmp, "init", "-q", "-b", "main", exception: true)
      system("git", "-C", tmp, "config", "maintenance.auto", "false", exception: true)
      2.times do |index|
        system("git", "-C", tmp, "-c", "user.email=spec@example.com", "-c", "user.name=spec",
               "commit", "-q", "--allow-empty", "-m", "c#{index}", exception: true)
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

  describe "coverage JSON input errors" do
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
      expect(stderr.string).to include('"coverage" must be an object')
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

  describe "run subcommand" do
    it "errors and exits 1 when no command is given" do
      expect(run("run")).to eq(1)
      expect(stderr.string).to include("missing command")
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

  describe "report subcommand" do
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

    it "prints the All Files totals" do
      expect(run("report", "--input", json_path)).to eq(0)
      expect(stdout.string).to include("All Files")
      expect(stdout.string).to match(%r{Line:\s+80\.00%\s+\(80 / 100\)})
      expect(stdout.string).to match(%r{Branch:\s+90\.00%\s+\(9 / 10\)})
    end

    it "skips a criterion with zero relevant entries" do
      expect(run("report", "--input", json_path)).to eq(0)
      expect(stdout.string).not_to include("Method:")
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

    it "errors when the input file is missing" do
      expect(run("report", "--input", "/no/such.json")).to eq(1)
      expect(stderr.string).to include("not found")
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

      it_behaves_like "a --no-color subcommand" do
        let(:no_color_argv) { ["report", "--input", json_path, "--no-color"] }
      end
    end
  end

  describe "tests subcommand" do
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
      expect(stderr.string).to include("no test contexts recorded")
      expect(stderr.string).to include("track_tests")
    end

    # A found-but-wrong-typed entry is malformed input, not a missing
    # file — the same distinction the coverage subcommand draws.
    it "reports a wrong-typed entry as invalid input, not as missing" do
      File.write(json_path, JSON.dump(payload.merge("coverage" => {result_file => "junk"})))
      expect(run("tests", "--input", json_path, "lib/result.rb")).to eq(1)
      expect(stderr.string).to include("entry for lib/result.rb must be an object")
      expect(stderr.string).not_to include("no entry")
    end

    it "documents its --json in the usage text" do
      expect(run("help")).to eq(0)
      expect(stdout.string).to include("tests options:")
    end

    it "reports an unknown file like the coverage subcommand does" do
      expect(run("tests", "--input", json_path, "lib/nope.rb")).to eq(1)
      expect(stderr.string).to include("no entry for lib/nope.rb")
    end

    it "names the candidates for an ambiguous subpath" do
      payload["coverage"][result_file.sub("/lib/", "/app/")] = {"lines" => [1]}
      File.write(json_path, JSON.dump(payload))

      expect(run("tests", "--input", json_path, "result.rb")).to eq(1)
      expect(stderr.string).to include("matches 2 files")
    end

    it "rejects a non-positive line number as a parse error" do
      expect(run("tests", "--input", json_path, "lib/result.rb:0")).to eq(1)
      expect(stderr.string).to include("line number must be positive")
    end

    it "treats a malformed per-file contexts table as invalid input" do
      [{"9" => "6"}, {"x" => "6"}, {"0" => "zz"}, "junk"].each do |malformed|
        payload["coverage"][result_file]["contexts"] = malformed
        File.write(json_path, JSON.dump(payload))
        stderr.truncate(0) && stderr.rewind
        expect(run("tests", "--input", json_path, "lib/result.rb")).to eq(1), "expected 1 for #{malformed.inspect}"
        expect(stderr.string).to include("isn't valid")
      end
    end

    it "treats a non-object coverage section as invalid input for a file query" do
      File.write(json_path, JSON.dump(payload.merge("coverage" => "junk")))
      expect(run("tests", "--input", json_path, "lib/result.rb")).to eq(1)
      expect(stderr.string).to include("isn't valid")
    end

    it "treats a malformed document-level contexts list as invalid input" do
      File.write(json_path, JSON.dump(payload.merge("contexts" => "junk")))
      expect(run("tests", "--input", json_path)).to eq(1)
      expect(stderr.string).to include("isn't valid")
    end

    describe "--redundant" do
      let(:other_file) { "/abs/project/lib/other.rb" }

      # Four contexts: :10 uniquely covers line 2 of result.rb and shares
      # line 3, :20 covers only that shared line, :30 uniquely covers
      # other.rb, and :40 ran without covering anything.
      let(:payload) do
        {
          "contexts" => ["spec/a_spec.rb:10", "spec/b_spec.rb:20", "spec/c_spec.rb:30", "spec/d_spec.rb:40"],
          "coverage" => {
            result_file => {"lines" => [nil, 1, 2, 0], "contexts" => {"0" => "6", "1" => "4"}},
            other_file => {"lines" => [1], "contexts" => {"2" => "1"}},
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
        payload["coverage"][result_file]["contexts"] = {"0" => "6", "1" => "6"}
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
      # all-or-nothing tolerance the targeted queries apply.
      it "treats a malformed contexts table anywhere in the sweep as invalid input" do
        [{"9" => "1"}, "junk"].each do |malformed|
          payload["coverage"][other_file]["contexts"] = malformed
          File.write(json_path, JSON.dump(payload))
          stderr.truncate(0) && stderr.rewind
          expect(run("tests", "--input", json_path, "--redundant")).to eq(1), "expected 1 for #{malformed.inspect}"
          expect(stderr.string).to include("isn't valid")
        end
      end

      it "treats a non-object coverage section as invalid input for the bare sweep" do
        File.write(json_path, JSON.dump(payload.merge("coverage" => "junk")))
        expect(run("tests", "--input", json_path, "--redundant")).to eq(1)
        expect(stderr.string).to include("isn't valid")
      end

      it "treats a wrong-typed entry anywhere in the sweep as invalid input" do
        payload["coverage"][quiet_file] = "junk"
        File.write(json_path, JSON.dump(payload))
        expect(run("tests", "--input", json_path, "--redundant")).to eq(1)
        expect(stderr.string).to include("entry for #{quiet_file} must be an object")
      end

      it "documents --redundant in the usage text" do
        expect(run("help")).to eq(0)
        expect(stdout.string).to include("--redundant")
      end
    end
  end

  describe "show subcommand" do
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
      payload["coverage"][File.join(SimpleCov.root, "lib/rooted.rb")] = {"lines" => [1, 0, 0, nil, 0]}
      payload["coverage"][File.join(tmp, "lib/covered.rb")] = {"lines" => [1, 1]}
      payload["coverage"][File.join(tmp, "lib/junk.rb")] = "junk"
      File.write(json_path, JSON.dump(payload))

      expect(run("show", "--input", json_path, "--uncovered-only")).to eq(0)
      expect(stdout.string).to eq(<<~OUT)
        #{code_path}:3,6-8,10
        lib/rooted.rb:2-3,5
      OUT
    end

    it "reports a missing input on a bare sweep like everywhere else" do
      expect(run("show", "--input", File.join(tmp, "nope.json"), "--uncovered-only")).to eq(1)
      expect(stderr.string).to include("not found")
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
      expect(stderr.string).to include("no line coverage")
    end

    it "reports an unknown file like the coverage subcommand does" do
      expect(run("show", "--input", json_path, "lib/nope.rb")).to eq(1)
      expect(stderr.string).to include("no entry for lib/nope.rb")
    end

    it "reports a wrong-typed entry as invalid input" do
      File.write(json_path, JSON.dump("coverage" => {code_path => "junk"}))
      expect(run("show", "--input", json_path, "lib/code.rb")).to eq(1)
      expect(stderr.string).to include("entry for lib/code.rb must be an object")
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

  describe "uncovered subcommand" do
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
                                  "total_lines" => 10, "covered_lines" => 1, "lines_covered_percent" => 10.0
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
        expect(stderr.string).to include("only github is supported")
      end

      it "refuses to combine --annotate with --json" do
        expect(run("uncovered", "--input", json_path, "--annotate", "github", "--json")).to eq(1)
        expect(stderr.string).to include("--json")
      end
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

  describe "merge subcommand" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-merge-spec-") }
    let(:a) { File.join(tmp, "a.json") }
    let(:b) { File.join(tmp, "b.json") }
    let(:out) { File.join(tmp, "merged.json") }
    # Use a real on-disk file inside SimpleCov.root so the default
    # root_filter doesn't strip it during result construction.
    let(:file) { File.expand_path("spec/fixtures/sample.rb", SimpleCov.root) }

    after { FileUtils.remove_entry(tmp) }

    def write_resultset(path, command_name, file_path, lines)
      File.write(path, JSON.dump(
                         command_name => {
                           "coverage" => {file_path => {"lines" => lines}},
                           "timestamp" => Time.now.to_i
                         }
                       ))
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
      expect(stderr.string).to include("cannot be read")
      expect(stderr.string).to include(tmp)
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
      expect(stderr.string).to include("warning")
      expect(stderr.string).to include('"RSpec"')
      expect(stderr.string).to include("appears in 2 input files")
    end

    it "doesn't write the output file under --dry-run" do
      write_resultset(a, "worker_1", file, [1, 0, nil])

      expect(run("merge", "--output", out, "--dry-run", a)).to eq(0)
      expect(File.exist?(out)).to be false
      expect(stdout.string).to include("would write")
      expect(stdout.string).to include(out)
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

  describe "diff subcommand" do
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

  describe "ratchet subcommand" do
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

  describe "history subcommand" do
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

    it "errors when the file is not a history" do
      File.write(input, JSON.dump("something" => "else"))

      expect(run_history).to eq(1)
      expect(stderr.string).to include("not a SimpleCov history file")
    end

    it "errors when the file is not JSON" do
      File.write(input, "{")

      expect(run_history).to eq(1)
      expect(stderr.string).to include("not valid JSON")
    end

    it "errors when the file is JSON but not an object" do
      File.write(input, "[]")

      expect(run_history).to eq(1)
      expect(stderr.string).to include("not a SimpleCov history file")
    end

    it "errors when the path cannot be read as a file" do
      expect(run("history", "--input", tmp)).to eq(1)
      expect(stderr.string).to include("simplecov history:")
    end

    it "rejects a stray positional argument" do
      expect(run("history", "stray")).to eq(1)
      expect(stderr.string).to include('unexpected argument "stray"')
    end
  end

  describe "dead-code subcommand" do
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

  describe "CoverageFile.lookup" do
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
  end

  describe "patch subcommand" do
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

    def init_repo
      git("init", "-q", "-b", "main")
      git("config", "user.email", "t@example.com")
      git("config", "user.name", "Test")
      # git 2.46+ forks a detached `git maintenance` after commits; its
      # transient .git/objects/maintenance.lock races the after-hook's
      # directory removal, so the fixture repo opts out.
      git("config", "maintenance.auto", "false")
      git("config", "gc.auto", "0")
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

    it "undoes git's C-quoting escapes" do
      unquote = SimpleCov::CLI::Patch::ChangedLines.method(:unquote)
      expect(unquote.call(%("b/a\\tb.rb"))).to eq("b/a\tb.rb")
      expect(unquote.call(%("b/caf\\303\\251.rb"))).to eq("b/café.rb")
      expect(unquote.call(%("b/a\\zb.rb"))).to eq("b/azb.rb") # unknown escape keeps its letter
      expect(unquote.call("b/plain.rb")).to eq("b/plain.rb")
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

  describe "serve subcommand" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-serve-spec-") }

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

    # End-to-end through `run`: spin the full entry point in a thread,
    # hit it, then signal Ctrl-C to stop. Exercises `run`, `announce`,
    # the serve_loop exit path, and the ensure-time `server.close`.
    it "serves the report end-to-end through the run entry point" do
      File.write(File.join(tmp, "index.html"), "<html>via-run</html>")
      allow(described_class).to receive(:coverage_dir).and_return(tmp)

      announced = Queue.new
      original_announce = described_class::Serve.method(:announce)
      allow(described_class::Serve).to receive(:announce) do |stdout, server, dir|
        announced << "http://#{server.addr[3]}:#{server.addr[1]}/"
        original_announce.call(stdout, server, dir)
      end

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
        thread.join(2)
      end
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

  describe "open subcommand" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-open-spec-") }

    after { FileUtils.remove_entry(tmp) }

    it "errors when the report file is missing" do
      expect(run("open", "--report", File.join(tmp, "missing.html"))).to eq(1)
      expect(stderr.string).to include("not found")
    end

    it "shells out to the platform opener with the report path" do
      report = File.join(tmp, "index.html")
      File.write(report, "<html></html>")
      allow(SimpleCov::CLI::Open).to receive_messages(browser_opener: ["open"], system: true)

      expect(run("open", "--report", report)).to eq(0)
      expect(SimpleCov::CLI::Open).to have_received(:system).with("open", report)
    end

    it "errors when the platform has no known opener" do
      report = File.join(tmp, "index.html")
      File.write(report, "<html></html>")
      allow(SimpleCov::CLI::Open).to receive(:browser_opener).and_return(nil)

      expect(run("open", "--report", report)).to eq(1)
      expect(stderr.string).to include("no known opener")
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

      it "picks `cmd /c start` on Windows" do
        stub_const("RbConfig::CONFIG", RbConfig::CONFIG.merge("host_os" => "mswin64"))
        expect(SimpleCov::CLI::Open.browser_opener).to eq(["cmd", "/c", "start", ""])
      end

      it "picks `xdg-open` on Linux/BSD/Solaris" do
        stub_const("RbConfig::CONFIG", RbConfig::CONFIG.merge("host_os" => "linux-gnu"))
        expect(SimpleCov::CLI::Open.browser_opener).to eq(["xdg-open"])
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
