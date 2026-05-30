# frozen_string_literal: true

require "helper"
require "net/http"
require "simplecov/cli"
require "socket"
require "stringio"
require "tmpdir"

RSpec.describe SimpleCov::CLI do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }

  def run(*argv)
    described_class.run(argv, stdout: stdout, stderr: stderr)
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

      it "skips colorization when --no-color is passed, even with Color.enabled? on" do
        allow(SimpleCov::Color).to receive(:enabled?).and_return(true)
        expect(run("coverage", "--input", json_path, "--no-color", abs_filename)).to eq(0)
        expect(stdout.string).not_to include("\e[")
        expect(stdout.string).to match(/66\.67%/)
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

    it "errors when the input file is missing" do
      expect(run("report", "--input", "/no/such.json")).to eq(1)
      expect(stderr.string).to include("not found")
    end

    it "emits totals and groups as JSON under --json" do
      expect(run("report", "--input", json_path, "--json")).to eq(0)
      payload = JSON.parse(stdout.string)
      expect(payload["All Files"]).to include("lines" => {"percent" => 80.0, "covered" => 80, "total" => 100})
      expect(payload["All Files"]).to include("branches" => {"percent" => 90.0, "covered" => 9, "total" => 10})
      expect(payload["All Files"]).not_to include("methods")
      expect(payload["Models"]).to include("lines" => {"percent" => 80.0, "covered" => 40, "total" => 50})
    end

    context "with colorization" do
      it "colorizes percentages by threshold when Color.enabled? is true" do
        allow(SimpleCov::Color).to receive(:enabled?).and_return(true)
        expect(run("report", "--input", json_path)).to eq(0)
        # 80% is yellow, 90% is green
        expect(stdout.string).to match(/\e\[33m80\.00%\e\[0m/)
        expect(stdout.string).to match(/\e\[32m90\.00%\e\[0m/)
      end

      it "skips colorization when --no-color is passed" do
        allow(SimpleCov::Color).to receive(:enabled?).and_return(true)
        expect(run("report", "--input", json_path, "--no-color")).to eq(0)
        expect(stdout.string).not_to include("\e[")
      end
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

      it "skips colorization when --no-color is passed" do
        allow(SimpleCov::Color).to receive(:enabled?).and_return(true)
        expect(run("uncovered", "--input", json_path, "--no-color")).to eq(0)
        expect(stdout.string).not_to include("\e[")
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
      a = File.join(tmp, "a.json")
      b = File.join(tmp, "b.json")
      out = File.join(tmp, "merged.json")
      # Use a real on-disk file inside SimpleCov.root so the default
      # root_filter doesn't strip it during result construction.
      file = File.expand_path("spec/fixtures/sample.rb", SimpleCov.root)
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
      expect(run("merge", "--output", File.join(tmp, "out.json"), bad)).to eq(1)
      expect(stderr.string).to include("isn't valid JSON")
      expect(stderr.string).to include("bad.json")
    end

    it "surfaces a specific error when an input is structurally empty" do
      empty = File.join(tmp, "empty.json")
      File.write(empty, "{}")
      expect(run("merge", "--output", File.join(tmp, "out.json"), empty)).to eq(1)
      expect(stderr.string).to include("no resultset entries")
      expect(stderr.string).to include("empty.json")
    end

    it "surfaces a specific error when an input file doesn't exist" do
      expect(run("merge", "--output", File.join(tmp, "out.json"), File.join(tmp, "nope.json"))).to eq(1)
      expect(stderr.string).to include("not found")
      expect(stderr.string).to include("nope.json")
    end

    it "errors when --honor-timeout expires every input's entries" do
      a = File.join(tmp, "a.json")
      file = File.expand_path("spec/fixtures/sample.rb", SimpleCov.root)
      # Far enough in the past that any reasonable merge_timeout drops it.
      File.write(a, JSON.dump("worker_1" => {"coverage" => {file => {"lines" => [1]}},
                                             "timestamp" => Time.now.to_i - 86_400}))
      expect(run("merge", "--output", File.join(tmp, "merged.json"), "--honor-timeout", a)).to eq(1)
      expect(stderr.string).to include("no mergeable results")
    end

    it "warns when two input files share a command_name" do
      a = File.join(tmp, "a.json")
      b = File.join(tmp, "b.json")
      file = File.expand_path("spec/fixtures/sample.rb", SimpleCov.root)
      write_resultset(a, "RSpec", file, [1, 0, nil])
      write_resultset(b, "RSpec", file, [0, 1, nil])

      expect(run("merge", "--output", File.join(tmp, "merged.json"), a, b)).to eq(0)
      expect(stderr.string).to include("warning")
      expect(stderr.string).to include('"RSpec"')
      expect(stderr.string).to include("appears in 2 input files")
    end

    it "doesn't write the output file under --dry-run" do
      a = File.join(tmp, "a.json")
      out = File.join(tmp, "merged.json")
      file = File.expand_path("spec/fixtures/sample.rb", SimpleCov.root)
      write_resultset(a, "worker_1", file, [1, 0, nil])

      expect(run("merge", "--output", out, "--dry-run", a)).to eq(0)
      expect(File.exist?(out)).to be false
      expect(stdout.string).to include("would write")
      expect(stdout.string).to include(out)
    end

    it "silences the success status line under --quiet" do
      a = File.join(tmp, "a.json")
      out = File.join(tmp, "merged.json")
      file = File.expand_path("spec/fixtures/sample.rb", SimpleCov.root)
      write_resultset(a, "worker_1", file, [1, 0, nil])

      expect(run("merge", "--output", out, "--quiet", a)).to eq(0)
      expect(stdout.string).to be_empty
      expect(File.exist?(out)).to be true
    end

    it "accepts -q as the short alias for --quiet" do
      a = File.join(tmp, "a.json")
      out = File.join(tmp, "merged.json")
      file = File.expand_path("spec/fixtures/sample.rb", SimpleCov.root)
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

    it "errors when the baseline argument is missing" do
      expect(run("diff")).to eq(1)
      expect(stderr.string).to include("missing baseline argument")
    end

    it "errors when an input file isn't readable" do
      expect(run("diff", "--input", File.join(tmp, "nope.json"), baseline)).to eq(1)
      expect(stderr.string).to include("not found")
    end

    it "reports branch coverage deltas when both sides include branch data" do
      write_coverage(baseline,
                     "lib/a.rb" => {"covered_lines" => 80, "lines_covered_percent" => 80.0,
                                    "total_branches" => 20, "covered_branches" => 16,
                                    "branches_covered_percent" => 80.0})
      write_coverage(current,
                     "lib/a.rb" => {"covered_lines" => 80, "lines_covered_percent" => 80.0,
                                    "total_branches" => 20, "covered_branches" => 10,
                                    "branches_covered_percent" => 50.0})

      expect(run("diff", "--input", current, baseline)).to eq(0)
      expect(stdout.string).to include("lib/a.rb")
      expect(stdout.string).to match(/-\s*30\.00%\s+branches/)
    end

    it "reports method coverage deltas when both sides include method data" do
      write_coverage(baseline,
                     "lib/a.rb" => {"covered_lines" => 80, "lines_covered_percent" => 80.0,
                                    "total_methods" => 20, "covered_methods" => 18,
                                    "methods_covered_percent" => 90.0})
      write_coverage(current,
                     "lib/a.rb" => {"covered_lines" => 80, "lines_covered_percent" => 80.0,
                                    "total_methods" => 20, "covered_methods" => 15,
                                    "methods_covered_percent" => 75.0})

      expect(run("diff", "--input", current, baseline)).to eq(0)
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

    context "with colorization" do
      it "colorizes regressions red and improvements green when Color.enabled? is true" do
        allow(SimpleCov::Color).to receive(:enabled?).and_return(true)
        write_coverage(baseline, "lib/a.rb" => 80, "lib/b.rb" => 50)
        write_coverage(current,  "lib/a.rb" => 85, "lib/b.rb" => 30)

        expect(run("diff", "--input", current, baseline)).to eq(0)
        expect(stdout.string).to match(/\e\[31m-\s*20\.00% lines\e\[0m/)
        expect(stdout.string).to match(/\e\[32m\+\s*5\.00% lines\e\[0m/)
      end

      it "skips colorization when --no-color is passed" do
        allow(SimpleCov::Color).to receive(:enabled?).and_return(true)
        write_coverage(baseline, "lib/a.rb" => 80)
        write_coverage(current,  "lib/a.rb" => 70)

        expect(run("diff", "--input", current, "--no-color", baseline)).to eq(0)
        expect(stdout.string).not_to include("\e[")
      end
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

    describe ".resolve" do
      before do
        FileUtils.mkdir_p(File.join(tmp, "assets"))
        File.write(File.join(tmp, "index.html"), "<html></html>")
        File.write(File.join(tmp, "assets", "app.js"), "var x;")
      end

      it "maps `/` to index.html" do
        expect(described_class::Serve.resolve("/", tmp)).to eq(File.realpath(File.join(tmp, "index.html")))
      end

      it "serves an explicit asset" do
        expect(described_class::Serve.resolve("/assets/app.js", tmp))
          .to eq(File.realpath(File.join(tmp, "assets/app.js")))
      end

      it "strips query strings" do
        expect(described_class::Serve.resolve("/index.html?_=1", tmp))
          .to eq(File.realpath(File.join(tmp, "index.html")))
      end

      it "returns nil for a missing file" do
        expect(described_class::Serve.resolve("/missing.html", tmp)).to be_nil
      end

      it "blocks parent-directory traversal" do
        expect(described_class::Serve.resolve("/../secret.txt", tmp)).to eq(:forbidden)
      end

      it "maps a directory request to its index.html" do
        FileUtils.mkdir_p(File.join(tmp, "assets", "nested"))
        File.write(File.join(tmp, "assets", "nested", "index.html"), "ok")
        expect(described_class::Serve.resolve("/assets/nested", tmp))
          .to eq(File.realpath(File.join(tmp, "assets/nested/index.html")))
      end

      it "blocks a symlink that escapes root" do
        Dir.mktmpdir("simplecov-cli-serve-escape-") do |outside|
          File.write(File.join(outside, "secret.txt"), "shhh")
          File.symlink(File.join(outside, "secret.txt"), File.join(tmp, "leak"))
          expect(described_class::Serve.resolve("/leak", tmp)).to eq(:forbidden)
        end
      end
    end

    it "returns 403 for a path-traversal attempt" do
      FileUtils.mkdir_p(tmp)
      server = TCPServer.new("127.0.0.1", 0)
      thread = Thread.new { described_class::Serve.handle_connection(server.accept, tmp) }
      sock = TCPSocket.new("127.0.0.1", server.addr[1])
      # Raw request so the path isn't normalized by Net::HTTP / URI.
      sock.write("GET /../secret.txt HTTP/1.1\r\nHost: x\r\n\r\n")
      expect(sock.read).to start_with("HTTP/1.1 403")
    ensure
      sock&.close
      thread&.join(2)
      server&.close
    end

    it "exits 405 for non-GET requests" do
      FileUtils.mkdir_p(tmp)
      server = TCPServer.new("127.0.0.1", 0)
      thread = Thread.new do
        described_class::Serve.handle_connection(server.accept, tmp)
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
      expect { described_class::Serve.handle_connection(accepted, tmp) }.not_to raise_error
    ensure
      server&.close
    end

    it "closes its TCPServer cleanly when an error bubbles out of run" do
      FileUtils.mkdir_p(tmp)
      allow(described_class).to receive(:coverage_dir).and_return(tmp)
      allow(TCPServer).to receive(:new).and_raise(Errno::EADDRINUSE, "addr in use")
      expect { run("serve") }.to raise_error(Errno::EADDRINUSE)
    end

    # End-to-end through `run`: spin the full entry point in a thread,
    # hit it, then signal Ctrl-C to stop. Exercises `run`, `announce`,
    # the serve_loop exit path, and the ensure-time `server.close`.
    it "serves the report end-to-end through the run entry point" do
      FileUtils.mkdir_p(tmp)
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
      ensure
        thread.raise(Interrupt) if thread.alive?
        thread.join(2)
      end
    end

    # End-to-end: spin the real server on a random port, make a request,
    # assert the body comes back.
    it "actually serves the report over HTTP" do
      FileUtils.mkdir_p(tmp)
      File.write(File.join(tmp, "index.html"), "<html>hello</html>")
      allow(described_class).to receive(:coverage_dir).and_return(tmp)

      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]
      thread = Thread.new { described_class::Serve.serve_loop(server, tmp, StringIO.new) }
      begin
        require "net/http"
        response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/"))
        expect(response.code).to eq("200")
        expect(response.body).to include("<html>hello</html>")

        not_found = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/missing.html"))
        expect(not_found.code).to eq("404")
      ensure
        thread.raise(Interrupt) if thread.alive?
        thread.join(2)
        server.close unless server.closed?
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
end
