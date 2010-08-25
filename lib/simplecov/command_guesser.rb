#
# Helper that tries to find out what test suite is running (for SimpleCov.command_name)
#
module SimpleCov::CommandGuesser
  def self.guess(command)
    case command
      when /#{'test/functional/'}/
        "Functional Tests"
      when /#{'test/integration/'}/
        "Integration Tests"
      when /#{'test/'}/
        "Unit Tests"
      when /cucumber/, /features/
        "Cucumber Features"
      when /#{'spec/'}/
        "RSpec"
      else
        return command
    end
  end
end