# frozen_string_literal: true

require "coverage"
require "helper"
require "net/http"
require "open3"
require "simplecov/cli"
require "socket"
require "stringio"
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

  describe "dispatch" do
    it "prints usage and exits 0 with no arguments" do
      expect(run).to eq(0)
      expect(stdout.string).to include("Usage:")
    end

    it "prints usage on `help`" do
      expect(run("help")).to eq(0)
      expect(stdout.string).to include("Commands:")
    end

    it "complains and exits non-zero on an unknown command" do
      expect(run("nope")).to eq(1)
      expect(stderr.string).to include('unknown command "nope"')
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

  describe ".coverage_dir" do
    # Reset memoization between examples so each one sees a fresh
    # discovery from its own cwd.
    around do |example|
      previous = described_class.instance_variable_get(:@coverage_dir)
      described_class.instance_variable_set(:@coverage_dir, nil)
      example.run
    ensure
      described_class.instance_variable_set(:@coverage_dir, previous)
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
      ["show", ->(bad, _good) { ["show", "--input", bad, "lib/a.rb"] }]
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

  describe "coverage subcommand" do
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

    it_behaves_like "a --no-color subcommand" do
      let(:no_color_argv) { ["show", "--input", json_path, "--no-color", "lib/code.rb"] }
    end

    it "documents itself in the usage text" do
      expect(run("help")).to eq(0)
      expect(stdout.string).to include("show options:")
    end
  end

  describe "affected subcommand" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-affected-spec-") }
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
          "toplevel_test.rb:99"
        ],
        "coverage" => {
          File.join(tmp, "lib/result.rb") => {"lines" => [nil, 1, 2, 0], "contexts" => {"0" => "6", "1" => "4"}},
          File.join(tmp, "lib/quiet.rb") => {"lines" => [1, nil]},
          File.join(tmp, "lib/odd.rb") => {"lines" => [1], "contexts" => {"2" => "1"}},
          File.join(tmp, "lib/stale.rb") => {"lines" => [1], "contexts" => {"3" => "1"}}
        }
      }
    end

    def file!(path, content = "# original\n")
      full = File.join(tmp, path)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, content)
    end

    def commit!(message)
      system("git", "-C", tmp, "add", "-A", exception: true)
      system("git", "-C", tmp, "-c", "user.email=spec@example.com", "-c", "user.name=spec",
             "commit", "-qm", message, exception: true)
    end

    before do
      file!("lib/result.rb")
      file!("lib/quiet.rb")
      file!("lib/odd.rb")
      file!("lib/stale.rb")
      file!("spec/result_spec.rb")
      file!("spec/source_file_spec.rb")
      file!("spec/helper.rb")
      file!("Gemfile.lock")
      file!(".gitignore", "coverage.json\nout.txt\n")
      system("git", "-c", "init.defaultBranch=main", "init", "-q", tmp, exception: true)
      # git 2.46+ forks a detached `git maintenance` after commits; its
      # transient .git/objects/maintenance.lock races the after-hook's
      # directory removal, so the fixture repo opts out.
      system("git", "-C", tmp, "config", "maintenance.auto", "false", exception: true)
      system("git", "-C", tmp, "config", "gc.auto", "0", exception: true)
      commit!("init")
      File.write(json_path, JSON.dump(payload))
    end

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
      expect(stderr.string).to include("git working tree")
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
      expect(stderr.string).to include("OddTest#test_odd").and include("no file location")
      expect(stderr.string).to include("falling back to the full suite")
    end

    it "falls back when the map names a test file that no longer exists" do
      file!("lib/stale.rb", "# changed\n")
      expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      expect(stdout.string).to be_empty
      expect(stderr.string).to include("spec/ghost_spec.rb no longer exists")
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
      expect(stderr.string).to include("entry for lib/result.rb must be an object")
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
    def build_repo(base:, head:, line_hits:, branches: nil, file: "lib/foo.rb", cover: true)
      init_repo
      write(file, base)
      commit("base")
      git("checkout", "-q", "-b", "feature")
      write(file, head)
      commit("head")
      write_report(file, line_hits, branches) if cover
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

    def write_report(file, line_hits, branches)
      payload = {"lines" => line_hits}
      payload["branches"] = branches if branches
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

    it "omits the branch column for a line-only report" do
      build_repo(base: "a\n", head: "a\nb\n", line_hits: [1, 1])

      run_in_repo("patch", "--base", "main", "--input", cov)
      expect(stdout.string).not_to include("branches")
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

  describe "clean subcommand" do
    let(:tmp) { Dir.mktmpdir("simplecov-cli-clean-spec-") }

    before do
      allow(described_class).to receive(:coverage_dir).and_return(tmp)
      FileUtils.mkdir_p(File.join(tmp, "assets"))
      File.write(File.join(tmp, "index.html"), "<html></html>")
      File.write(File.join(tmp, "coverage.json"), "{}")
    end

    after { FileUtils.rm_rf(tmp) }

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
      expect(stdout.string).to include("doesn't exist")
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
  describe "colorizing subcommands in the standalone CLI process" do
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
