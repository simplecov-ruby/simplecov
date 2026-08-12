# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "sandbox Bundler environment", :sandbox do
  def reported_gemfile
    command = "bundle exec ruby -rbundler -e 'puts Bundler.default_gemfile'"
    run_command_and_expect_success(command).output.strip
  end

  it "activates a copied project's Gemfile instead of the host definition" do
    setup_project("faked_project")

    expect(reported_gemfile).to eq(File.join(sandbox_dir, "Gemfile"))
  end

  it "uses the host Gemfile for a fixture that does not ship one" do
    setup_project("old_coverage_json")

    expect(reported_gemfile).to eq(File.join(SandboxProject::PROJECT_ROOT, "Gemfile"))
  end
end
