# frozen_string_literal: true

require "helper"
require "open3"
require "tmpdir"

RSpec.describe "frontend asset compilation" do
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

  it "mangles real custom properties but leaves BEM class modifiers alone" do
    css = ".cell--numerator{text-align:right;color:var(--example-token)}.x{--example-token:#fff}"
    command = %(load "./Rakefile"; print mangle_css_custom_properties(#{css.inspect}))
    output, _error, status = Open3.capture3("bundle", "exec", "ruby", "-rrake", "-e", command,
                                            chdir: SimpleCov.root.to_s)

    expect(status).to be_success
    expect(output).to include(".cell--numerator{text-align:right")
    expect(output).not_to include("--example-token")
    expect(output).to match(/color:var\(--[a-z]{1,2}\)/)
  end
end # rubocop:enable RSpec/DescribeClass
