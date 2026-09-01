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

  def guess_for(command)
    guesser.original_run_command = command
    guesser.guess
  end

  def expect_guesses(label, *commands)
    commands.each { |command| expect(guess_for(command)).to(eq(label), command.inspect) }
  end

  it 'correctly guesses "Unit Tests" for unit tests' do
    expect_guesses("Unit Tests", "/some/path/test/units/foo_bar_test.rb", "test/units/foo.rb",
      "test/foo.rb", "test/{models,helpers,unit}/**/*_test.rb")
  end

  it 'correctly guesses "Functional Tests" for functional tests' do
    expect_guesses("Functional Tests", "/some/path/test/functional/foo_bar_controller_test.rb",
      "test/{controllers,mailers,functional}/**/*_test.rb")
  end

  it 'correctly guesses "Integration Tests" for integration tests' do
    expect_guesses("Integration Tests", "/some/path/test/integration/foo_bar_controller_test.rb",
      "test/integration/**/*_test.rb")
  end

  it 'correctly guesses "Cucumber Features" for cucumber features' do
    expect_guesses("Cucumber Features", "features", "cucumber")
  end

  it 'correctly guesses "RSpec" for RSpec' do
    expect_guesses("RSpec", "/some/path/spec/foo.rb")
  end

  it "ignores framework keywords that do not start a path segment" do
    expect_guesses("RSpec", "/opt/rubies/latest/bin/ruby spec/foo_spec.rb")
    expect_guesses("Cucumber Features", "/usr/local/contest/bin/ruby features/foo.feature")
  end

  it "ignores framework keywords that do not start a path segment within arguments" do
    expect_guesses("RSpec", "/usr/local/bin/ruby spec/greatest/foo_spec.rb")
    expect_guesses("Cucumber Features", "/usr/local/bin/ruby features/contest/foo.feature")
  end

  it "treats a backslash as a path segment separator" do
    expect_guesses("Cucumber Features", 'C:\Ruby\bin\ruby.exe features\foo.feature')
    expect_guesses("RSpec", 'C:\Ruby\bin\ruby.exe spec\foo_spec.rb')
  end

  it "still ignores a keyword mid-segment in a backslash path" do
    expect_guesses("Cucumber Features", 'C:\opt\contest\bin\ruby features\foo.feature')
    expect_guesses("RSpec", 'C:\opt\latest\bin\ruby spec\foo_spec.rb')
  end

  it "labels a suite by its executable despite a test/ substring in the path" do
    expect_guesses("RSpec", "/opt/rubies/latest/bin/rspec", "/home/dev/greatest/bin/rspec spec/foo_spec.rb")
    expect_guesses("Cucumber Features", "/usr/local/contest/bin/cucumber")
  end

  it "lets the invoked executable outrank the arguments" do
    expect_guesses("RSpec", "/usr/local/bin/rspec features")
    expect_guesses("Cucumber Features", "/usr/local/bin/cucumber test/integration")
  end

  it "recognizes the executable regardless of the path leading to it" do
    expect_guesses("RSpec", "/Users/me/.local/share/mise/installs/ruby/latest/bin/rspec", "bin/rspec",
      "rspec.bat")
  end

  it "falls through to the path patterns for generic runners" do
    expect_guesses("Functional Tests",
      "/gems/rake-13.4.2/lib/rake/rake_test_loader.rb test/functional/foo_test.rb")
    expect_guesses("Integration Tests", "/opt/rubies/latest/bin/ruby test/integration/foo_test.rb")
  end

  it "recognizes an executable whose path contains spaces" do
    guesser.original_run_command = "/opt/My Ruby/bin/rspec features"
    guesser.original_program_name = "/opt/My Ruby/bin/rspec"
    expect(guesser.guess).to eq("RSpec")
  end

  it "derives the program name from the command when it wasn't recorded separately" do
    guesser.original_run_command = "/opt/rubies/latest/bin/rspec features"
    expect(guesser.original_program_name).to eq("/opt/rubies/latest/bin/rspec")
  end

  it "guesses from the program name it derived from the command" do
    expect_guesses("RSpec", "/opt/rubies/latest/bin/rspec features")
  end

  it "forgets a stale program name when the command is reassigned" do
    guesser.original_program_name = "/opt/My Ruby/bin/cucumber"
    guesser.original_run_command = "/usr/local/bin/rspec spec/foo_spec.rb"
    expect(guesser.guess).to eq("RSpec")
  end

  it "falls back to the defined constants when no command was recorded" do
    expect_guesses("RSpec", nil, "   ")
  end

  it "defaults to RSpec because RSpec constant is defined" do
    expect_guesses("RSpec", "some_arbitrary_command with arguments")
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
    before do
      guesser.original_run_command = "/some/path/unremarkable.rb"
      guesser.original_program_name = nil
      allow(described_class).to receive(:warn)
    end

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
      with_frameworks([["Absent", -> { false }], ["Present", -> { true }]]) do
        expect(guesser.guess).to eq("Present")
      end
    end

    it "says so when it recognizes nothing" do
      with_frameworks([["Absent", -> { false }]]) do
        expect(guesser.guess).to eq("Unknown Test Framework")
      end
    end

    it "warns when it recognizes nothing" do
      with_frameworks([["Absent", -> { false }]]) { guesser.guess }

      expect(described_class).to have_received(:warn).with(/failed to recognize the test framework/)
    end
  end
end
