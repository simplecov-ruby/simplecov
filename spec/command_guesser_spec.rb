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
    saved_program = described_class.original_program_name
    example.run
  ensure
    described_class.original_run_command = saved_command
    described_class.original_program_name = saved_program
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

  # https://github.com/simplecov-ruby/simplecov/issues/1249
  #
  # These run through a generic `ruby`, which the executable table deliberately
  # omits, so the path patterns decide the answer and the segment boundaries are
  # what's under test. Naming `rspec` or `cucumber` here would short-circuit
  # before the patterns ran and pass with or without the boundaries.
  it "ignores framework keywords that do not start a path segment" do
    guesser.original_run_command = "/opt/rubies/latest/bin/ruby spec/foo_spec.rb"
    expect(guesser.guess).to eq("RSpec")
    guesser.original_run_command = "/usr/local/contest/bin/ruby features/foo.feature"
    expect(guesser.guess).to eq("Cucumber Features")
  end

  it "ignores framework keywords that do not start a path segment within arguments" do
    guesser.original_run_command = "/usr/local/bin/ruby spec/greatest/foo_spec.rb"
    expect(guesser.guess).to eq("RSpec")
    guesser.original_run_command = "/usr/local/bin/ruby features/contest/foo.feature"
    expect(guesser.guess).to eq("Cucumber Features")
  end

  # A backslash separates path segments too, so anchoring only on `/` would
  # lose matches the unanchored patterns used to make on Windows arguments.
  # CI cannot catch this: windows-latest invokes with forward slashes, and a
  # recognized executable short-circuits before the patterns run. Reported by
  # @andriytyurnikov on #1251.
  #
  # The Cucumber cases are the ones that pin this. Under RSpec the constant
  # fallback answers "RSpec" anyway, so an RSpec expectation here would pass
  # with or without the backslash in the boundaries.
  it "treats a backslash as a path segment separator" do
    guesser.original_run_command = 'C:\Ruby\bin\ruby.exe features\foo.feature'
    expect(guesser.guess).to eq("Cucumber Features")
    guesser.original_run_command = 'C:\Ruby\bin\ruby.exe spec\foo_spec.rb'
    expect(guesser.guess).to eq("RSpec")
  end

  it "still ignores a keyword mid-segment in a backslash path" do
    guesser.original_run_command = 'C:\opt\contest\bin\ruby features\foo.feature'
    expect(guesser.guess).to eq("Cucumber Features")
    guesser.original_run_command = 'C:\opt\latest\bin\ruby spec\foo_spec.rb'
    expect(guesser.guess).to eq("RSpec")
  end

  # The originally reported shape: the interpreter path decides nothing, the
  # executable does. Kept alongside the pattern examples above because these are
  # the exact commands from the issue.
  it "labels a suite by its executable despite a test/ substring in the path" do
    guesser.original_run_command = "/opt/rubies/latest/bin/rspec"
    expect(guesser.guess).to eq("RSpec")
    guesser.original_run_command = "/usr/local/contest/bin/cucumber"
    expect(guesser.guess).to eq("Cucumber Features")
    guesser.original_run_command = "/home/dev/greatest/bin/rspec spec/foo_spec.rb"
    expect(guesser.guess).to eq("RSpec")
  end

  it "lets the invoked executable outrank the arguments" do
    guesser.original_run_command = "/usr/local/bin/rspec features"
    expect(guesser.guess).to eq("RSpec")
    guesser.original_run_command = "/usr/local/bin/cucumber test/integration"
    expect(guesser.guess).to eq("Cucumber Features")
  end

  it "recognizes the executable regardless of the path leading to it" do
    guesser.original_run_command = "/Users/me/.local/share/mise/installs/ruby/latest/bin/rspec"
    expect(guesser.guess).to eq("RSpec")
    guesser.original_run_command = "bin/rspec"
    expect(guesser.guess).to eq("RSpec")
    guesser.original_run_command = "rspec.bat"
    expect(guesser.guess).to eq("RSpec")
  end

  it "falls through to the path patterns for generic runners" do
    guesser.original_run_command =
      "/gems/rake-13.4.2/lib/rake/rake_test_loader.rb test/functional/foo_test.rb"
    expect(guesser.guess).to eq("Functional Tests")
    guesser.original_run_command = "/opt/rubies/latest/bin/ruby test/integration/foo_test.rb"
    expect(guesser.guess).to eq("Integration Tests")
  end

  # `original_run_command` joins $PROGRAM_NAME and ARGV with a space, so the
  # program path can't be recovered from it once it contains one. `defaults.rb`
  # records it separately for exactly this reason.
  it "recognizes an executable whose path contains spaces" do
    guesser.original_run_command = "/opt/My Ruby/bin/rspec features"
    guesser.original_program_name = "/opt/My Ruby/bin/rspec"
    expect(guesser.guess).to eq("RSpec")
  end

  it "derives the program name from the command when it wasn't recorded separately" do
    guesser.original_run_command = "/opt/rubies/latest/bin/rspec features"
    expect(guesser.original_program_name).to eq("/opt/rubies/latest/bin/rspec")
    expect(guesser.guess).to eq("RSpec")
  end

  it "forgets a stale program name when the command is reassigned" do
    guesser.original_program_name = "/opt/My Ruby/bin/cucumber"
    guesser.original_run_command = "/usr/local/bin/rspec spec/foo_spec.rb"
    expect(guesser.guess).to eq("RSpec")
  end

  it "falls back to the defined constants when no command was recorded" do
    guesser.original_run_command = nil
    expect(guesser.guess).to eq("RSpec")
    guesser.original_run_command = "   "
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
