# frozen_string_literal: true

require "helper"
require "simplecov/cli"
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
