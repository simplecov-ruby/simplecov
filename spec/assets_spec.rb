# frozen_string_literal: true

require "helper"
require "open3"
require "support/captured_runs"
require "tmpdir"

RSpec.describe "frontend asset compilation" do
  describe "a CSS minifier that exits unsuccessfully" do
    let(:failing_esbuild) do
      <<~SH
        #!/bin/sh
        cat >/dev/null
        echo "synthetic CSS failure" >&2
        exit 42
      SH
    end
    let(:run) do
      CapturedRuns.once(:failing_esbuild) do
        Dir.mktmpdir("simplecov-failing-esbuild-") do |tmp|
          esbuild = File.join(tmp, "esbuild")
          File.write(esbuild, failing_esbuild)
          FileUtils.chmod(0o755, esbuild)
          run_rakefile('minify_css("body {}", esbuild: "esbuild")',
            "PATH" => [tmp, ENV.fetch("PATH")].join(File::PATH_SEPARATOR))
        end
      end
    end
    let(:status) { run.last }
    let(:output) { run.first(2).join }

    before { skip "the fake esbuild is a POSIX shell script" if Gem.win_platform? }

    it "fails the compilation" do
      expect(status).not_to be_success
    end

    it "reports the minifier's exit status" do
      expect(output).to include("CSS compilation failed (exit 42)")
    end

    it "passes the minifier's own complaint through" do
      expect(output).to include("synthetic CSS failure")
    end
  end

  describe "mangling CSS custom properties" do
    let(:css) { ".cell--numerator{text-align:right;color:var(--example-token)}.x{--example-token:#fff}" }
    let(:run) do
      CapturedRuns.once(:mangle_css) { run_rakefile("print mangle_css_custom_properties(#{css.inspect})") }
    end
    let(:status) { run.last }
    let(:output) { run.first }

    it "succeeds" do
      expect(status).to be_success
    end

    it "leaves a BEM class modifier alone" do
      expect(output).to include(".cell--numerator{text-align:right")
    end

    it "renames the custom property" do
      expect(output).not_to include("--example-token")
    end

    it "renames it to a short alias" do
      expect(output).to match(/color:var\(--[a-z]{1,2}\)/)
    end
  end

  def run_rakefile(snippet, env = {})
    Open3.capture3(env, "bundle", "exec", "ruby", "-rrake", "-e", %(load "./Rakefile"; #{snippet}),
      chdir: SimpleCov.root.to_s)
  end
end # rubocop:enable RSpec/DescribeClass
