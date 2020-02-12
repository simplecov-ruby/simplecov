# frozen_string_literal: true

require "spec_helper"
require "open3"

RSpec.describe "testing through the executable" do
  it "can test the greet functionality" do
    stdout, = Open3.capture3("bin/cli_acceptance greet Huha")

    expect(stdout).to eq "Hello there Huha\n"
  end

  it "can add things together" do
    stdout, = Open3.capture3("bin/cli_acceptance add 40 2")

    expect(stdout).to eq "42\n"
  end
end
