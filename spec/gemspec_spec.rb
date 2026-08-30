# frozen_string_literal: true

require "open3"

RSpec.describe "gemspec sanity" do
  after do
    File.delete(Dir.glob("simplecov-*.gem").first)
  end

  let(:build) do
    Bundler.with_original_env do
      Open3.capture3("gem build simplecov.gemspec")
    end
  end

  it "has no warnings" do
    expect(build[1]).not_to include("WARNING")
  end

  it "succeeds" do
    expect(build[2]).to be_success
  end
end
