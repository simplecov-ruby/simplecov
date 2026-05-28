# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::CommandGuesser do
  subject(:guesser) { described_class }

  # `original_run_command` is class-level state on CommandGuesser, and
  # `SimpleCov.command_name` lazy-caches `CommandGuesser.guess` into an
  # instance variable that persists for the whole process. Without
  # restoring the command here, a later spec that triggers the first
  # call to `SimpleCov.command_name` would lock in whatever value this
  # spec happened to leave behind (e.g. "Cucumber Features").
  around do |example|
    saved_command = described_class.original_run_command
    example.run
  ensure
    described_class.original_run_command = saved_command
  end

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
    with_env("PARALLEL_TEST_GROUPS" => "2", "TEST_ENV_NUMBER" => "1") do
      expect(guesser.guess).to eq("RSpec (1/2)")
    end
  end

  it 'treats an empty TEST_ENV_NUMBER as worker "1"' do
    guesser.original_run_command = "/some/path/spec/foo.rb"
    with_env("PARALLEL_TEST_GROUPS" => "2", "TEST_ENV_NUMBER" => "") do
      expect(guesser.guess).to eq("RSpec (1/2)")
    end
  end
end
