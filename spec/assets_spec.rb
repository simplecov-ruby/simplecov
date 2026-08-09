# frozen_string_literal: true

require "helper"
require "open3"
require "tmpdir"

RSpec.describe "frontend asset compilation" do # rubocop:disable RSpec/DescribeClass
  it "fails when the CSS minifier exits unsuccessfully" do
    skip "the fake esbuild is a POSIX shell script" if Gem.win_platform?

    Dir.mktmpdir("simplecov-failing-esbuild-") do |tmp|
      esbuild = File.join(tmp, "esbuild")
      File.write(esbuild, <<~SH)
        #!/bin/sh
        cat >/dev/null
        echo "synthetic CSS failure" >&2
        exit 42
      SH
      FileUtils.chmod(0o755, esbuild)

      env = {"PATH" => [tmp, ENV.fetch("PATH")].join(File::PATH_SEPARATOR)}
      command = 'load "./Rakefile"; minify_css("body {}", esbuild: "esbuild")'
      output, error, status = Open3.capture3(env, "bundle", "exec", "ruby", "-rrake", "-e", command,
                                             chdir: SimpleCov.root.to_s)

      expect(status).not_to be_success
      expect(output + error).to include("CSS compilation failed (exit 42)").and include("synthetic CSS failure")
    end
  end
end # rubocop:enable RSpec/DescribeClass
