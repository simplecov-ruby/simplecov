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
      when /spec/
        "RSpec"
      else
        # If the command regexps fail, let's try checking defined constants.
        if defined?(RSpec)
          return "RSpec"
        elsif defined?(Test::Unit)
          return "Unit Tests"
        else
          return command
        end
    end
  end
end
