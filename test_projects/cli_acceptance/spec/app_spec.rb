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

RSpec.describe "direct testing from primary spec process" do

  require_relative "../lib/cli_acceptance"

  describe 'CLIAcceptance' do
    describe '#echo_two' do
      context "no args" do
        it "returns 2" do
          expect(CLIAcceptance.echo_two).to eq 2
        end
      end
      context "with 1 arg" do
        it "returns the args" do
          expect(CLIAcceptance.echo_two(1)).to eq 1
        end
      end
      context "with 3 arg" do
        it "returns the args" do
          expect(CLIAcceptance.echo_two(['a', true, 3])).to eq ['a', true, 3]
        end
      end
    end
  end
end
