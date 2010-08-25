require 'helper'

class TestCommandGuesser < Test::Unit::TestCase
  def self.should_guess_command_name(expectation, *argv)
    argv.each do |args|
      should "return '#{expectation}' for '#{args}'" do
        assert_equal expectation, SimpleCov::CommandGuesser.guess(args)
      end
    end
  end
  
  should_guess_command_name "Unit Tests", '/some/path/test/units/foo_bar_test.rb', 'test/units/foo.rb', 'test/foo.rb'
  should_guess_command_name "Functional Tests", '/some/path/test/functional/foo_bar_controller_test.rb'
  should_guess_command_name "Integration Tests", '/some/path/test/integration/foo_bar_controller_test.rb'  
  should_guess_command_name "Cucumber Features", 'features', 'cucumber', 'cucumber features'
  should_guess_command_name "RSpec", '/some/path/spec/foo.rb'
  should_guess_command_name "some_arbitrary_command with arguments", 'some_arbitrary_command with arguments'
end