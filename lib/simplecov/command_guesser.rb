#
# Helper that tries to find out what test suite is running (for SimpleCov.command_name)
#
module SimpleCov::CommandGuesser
  class << self
    # Storage for the original command line call that invoked the test suite.
    # This has got to be stored as early as possible because i.e. rake and test/unit 2
    # have a habit of tampering with ARGV, which makes i.e. the automatic distinction
    # between rails unit/functional/integration tests impossible without this cached
    # item.
    attr_accessor :original_run_command
    
    def guess
      from_command_line_options || from_defined_constants
    end
    
    private
    
    def from_command_line_options
      case original_run_command
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
          nil
      end
    end
  
    def from_defined_constants
      # If the command regexps fail, let's try checking defined constants.
      if defined?(RSpec)
        "RSpec"
      elsif defined?(Test::Unit)
        "Unit Tests"
      else
        # TODO: Provide link to docs/wiki article
        warn "SimpleCov failed to recognize the test framework and/or suite used. Please specify manually using SimpleCov.command_name 'Unit Tests'."
        'Unknown Test Framework'
      end
    end
  end
end