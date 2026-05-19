# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::CommandGuesser do
  subject(:guesser) { described_class }

  it 'correctly guesses "Unit Tests" for unit tests' do
    guesser.original_run_command = "/some/path/test/units/foo_bar_test.rb"
    expect(guesser.guess).to eq("Unit Tests")
    guesser.original_run_command = "test/units/foo.rb"
    expect(guesser.guess).to eq("Unit Tests")
    guesser.original_run_command = "test/foo.rb"
    expect(guesser.guess).to eq("Unit Tests")
    guesser.original_run_command = "test/{models,helpers,unit}/**/*_test.rb"
    expect(guesser.guess).to eq("Unit Tests")
  end

  it 'correctly guesses "Functional Tests" for functional tests' do
    guesser.original_run_command = "/some/path/test/functional/foo_bar_controller_test.rb"
    expect(guesser.guess).to eq("Functional Tests")
    guesser.original_run_command = "test/{controllers,mailers,functional}/**/*_test.rb"
    expect(guesser.guess).to eq("Functional Tests")
  end

  it 'correctly guesses "Integration Tests" for integration tests' do
    guesser.original_run_command = "/some/path/test/integration/foo_bar_controller_test.rb"
    expect(guesser.guess).to eq("Integration Tests")
    guesser.original_run_command = "test/integration/**/*_test.rb"
    expect(guesser.guess).to eq("Integration Tests")
  end

  it 'correctly guesses "Cucumber Features" for cucumber features' do
    guesser.original_run_command = "features"
    expect(guesser.guess).to eq("Cucumber Features")
    guesser.original_run_command = "cucumber"
    expect(guesser.guess).to eq("Cucumber Features")
  end

  it 'correctly guesses "RSpec" for RSpec' do
    guesser.original_run_command = "/some/path/spec/foo.rb"
    expect(guesser.guess).to eq("RSpec")
  end

  it "defaults to RSpec because RSpec constant is defined" do
    guesser.original_run_command = "some_arbitrary_command with arguments"
    expect(guesser.guess).to eq("RSpec")
  end

  it "appends parallel data" do
    guesser.original_run_command = "/some/path/spec/foo.rb"
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:[]).with("TEST_ENV_NUMBER").and_return("1")
    allow(ENV).to receive(:[]).with("PARALLEL_TEST_GROUPS").and_return("2")
    allow(ENV).to receive(:fetch).with("TEST_ENV_NUMBER", nil).and_return("1")
    allow(ENV).to receive(:fetch).with("PARALLEL_TEST_GROUPS", nil).and_return("2")
    expect(guesser.guess).to eq("RSpec (1/2)")
  end

  it 'treats an empty TEST_ENV_NUMBER as worker "1"' do
    guesser.original_run_command = "/some/path/spec/foo.rb"
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:[]).with("TEST_ENV_NUMBER").and_return("")
    allow(ENV).to receive(:[]).with("PARALLEL_TEST_GROUPS").and_return("2")
    allow(ENV).to receive(:fetch).with("TEST_ENV_NUMBER", nil).and_return("")
    allow(ENV).to receive(:fetch).with("PARALLEL_TEST_GROUPS", nil).and_return("2")
    expect(guesser.guess).to eq("RSpec (1/2)")
  end
end
