# frozen_string_literal: true

require "spec_helper"
require "open3"

# If you read this, this a simplified example setup of what's
# described in #853
# https://github.com/colszowka/simplecov/issues/853#issuecomment-582546760

RSpec.describe "testing through the executable" do
  it "can test the greet functionality" do
    stdout, = Open3.capture3("TEST_ENV_NUMBER=1 bin/cli_acceptance greet Huha")

    expect(stdout).to match "Hello there Huha\n"
  end

  it "can add things together" do
    stdout, = Open3.capture3("TEST_ENV_NUMBER=2 bin/cli_acceptance add 40 2")

    expect(stdout).to match "42\n"
  end
end
