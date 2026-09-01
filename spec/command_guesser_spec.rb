# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::CommandGuesser do
  subject(:guesser) { described_class }

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

  describe "the parallel worker label" do
    before { guesser.original_run_command = "/some/path/spec/foo.rb" }

    it "goes unlabelled when the pool size is unknown" do
      with_env("PARALLEL_TEST_GROUPS" => nil, "TEST_ENV_NUMBER" => "2") do
        expect(guesser.guess).to eq("RSpec")
      end
    end

    it "goes unlabelled when this worker's position is unknown" do
      with_env("PARALLEL_TEST_GROUPS" => "2", "TEST_ENV_NUMBER" => nil) do
        expect(guesser.guess).to eq("RSpec")
      end
    end

    it "labels a numbered worker by its own number" do
      with_env("PARALLEL_TEST_GROUPS" => "4", "TEST_ENV_NUMBER" => "3") do
        expect(guesser.guess).to eq("RSpec (3/4)")
      end
    end
  end

  describe "the invoked program" do
    it "recognizes an executable that carries an extension" do
      guesser.original_run_command = "/some/path/rspec.bat --format doc"
      guesser.original_program_name = nil
      expect(guesser.send(:from_executable_name)).to eq("RSpec")
    end

    it "recognizes an executable named without one" do
      guesser.original_run_command = "/some/path/cucumber features"
      guesser.original_program_name = nil
      expect(guesser.send(:from_executable_name)).to eq("Cucumber Features")
    end

    it "matches no pattern against a command that was never recorded" do
      guesser.original_run_command = nil
      guesser.original_program_name = nil
      expect(guesser.send(:from_command_line_options)).to be_nil
    end

    it "reads the program out of a command that begins with whitespace" do
      guesser.original_run_command = "  cucumber features"
      guesser.original_program_name = nil
      expect(guesser.original_program_name).to eq("cucumber")
    end

    it "guesses nothing from a command that was never recorded" do
      guesser.original_run_command = nil
      guesser.original_program_name = nil
      expect(guesser.original_program_name).to be_nil
    end
  end

  describe "falling back to the frameworks that are loaded" do
    def with_frameworks(list)
      singleton = described_class.singleton_class
      original = singleton.const_get(:DEFINED_CONSTANT_FRAMEWORKS)
      swap_frameworks(singleton, list)
      yield
    ensure
      swap_frameworks(singleton, original)
    end

    # rubocop:disable RSpec/RemoveConst
    def swap_frameworks(singleton, list)
      singleton.send(:remove_const, :DEFINED_CONSTANT_FRAMEWORKS)
      singleton.const_set(:DEFINED_CONSTANT_FRAMEWORKS, list)
      singleton.send(:private_constant, :DEFINED_CONSTANT_FRAMEWORKS)
    end
    # rubocop:enable RSpec/RemoveConst

    it "names the first framework whose constant is there" do
      guesser.original_run_command = "/some/path/unremarkable.rb"
      guesser.original_program_name = nil

      with_frameworks([["Absent", -> { false }], ["Present", -> { true }]]) do
        expect(guesser.guess).to eq("Present")
      end
    end

    it "says so when it recognizes nothing" do
      guesser.original_run_command = "/some/path/unremarkable.rb"
      guesser.original_program_name = nil
      allow(described_class).to receive(:warn)

      with_frameworks([["Absent", -> { false }]]) do
        expect(guesser.guess).to eq("Unknown Test Framework")
      end
      expect(described_class).to have_received(:warn).with(/failed to recognize the test framework/)
    end
  end
end
