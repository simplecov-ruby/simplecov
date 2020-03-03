@rspec

Feature:
  Coverage should include code run by subprocesses

  Background:
    Given I'm working on the project "subprocesses"

  Scenario: Coverage has seen the subprocess line
  When I open the coverage report generated with `bundle exec rspec spec/simple_spec.rb`
  Then I should see the groups:
    | name      | coverage | files |
    | All Files | 100.0%   | 1     |

  Scenario: The at_fork proc
  Given a file named ".simplecov" with:
    """
    SimpleCov.enable_for_subprocesses = true
    SimpleCov.command_name "parent process name"
    SimpleCov.at_fork do |_pid|
      SimpleCov.command_name "child process name"
      SimpleCov.start
    end
    """
  When I open the coverage report generated with `bundle exec rspec spec/simple_spec.rb`
  Then I should see the groups:
    | name      | coverage | files |
    | All Files | 100.0%   | 1     |
  And the report should be based upon:
      | child process name  |
      | parent process name |

  Scenario: The documentation on .simplecov_spawn
  When I open the coverage report generated with `bundle exec rspec spec/spawn_spec.rb`
  Then I should see the groups:
    | name      | coverage | files |
    | All Files | 100.0%   | 1     |
