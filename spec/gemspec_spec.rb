# frozen_string_literal: true

require "fileutils"
require "open3"
require "support/captured_runs"

RSpec.describe "gemspec sanity" do
  let(:build) do
    CapturedRuns.once(:gemspec_build) do
      Bundler.with_original_env do
        Open3.capture3("gem build simplecov.gemspec")
      end
    ensure
      FileUtils.rm_f(Dir.glob("simplecov-*.gem"))
    end
  end

  it "has no warnings" do
    expect(build[1]).not_to include("WARNING")
  end

  it "succeeds" do
    expect(build[2]).to be_success
  end
end
