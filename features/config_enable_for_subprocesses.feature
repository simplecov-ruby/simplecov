@rspec @process_fork

Feature:
  Coverage should include code run by subprocesses

  Background:
    Given I'm working on the project "subprocesses"

  Scenario: Coverage has seen the subprocess line
  When I open the coverage report generated with `bundle exec rspec spec/simple_spec.rb`
  Then I should see the groups:
    | name      | coverage | files |
    | All Files | 100.00%  | 1     |

  Scenario: The at_fork proc
  Given a file named ".simplecov" with:
    """
    SimpleCov.merge_subprocesses true
    SimpleCov.command_name "parent process name"
    SimpleCov.at_fork do |_pid|
      SimpleCov.command_name "child process name"
      SimpleCov.start
    end
    """
  When I open the coverage report generated with `bundle exec rspec spec/simple_spec.rb`
  Then I should see the groups:
    | name      | coverage | files |
    | All Files | 100.00%  | 1     |
  And the report should be based upon:
      | child process name  |
      | parent process name |

  # Reproduces #1227: a parent that hands its report to an external at_exit
  # owner (what the Minitest autorun deferral and the minitest plugin do)
  # passes external_at_exit = true into forked children, where the deferral
  # target can never fire. The child must reset the inherited state and
  # store its own resultset, or its coverage silently vanishes.
  Scenario: A parent deferring its report externally still merges forked children
  Given a file named ".simplecov" with:
    """
    SimpleCov.merge_subprocesses true
    SimpleCov.command_name "parent process name"
    SimpleCov.add_filter /command/
    SimpleCov.add_filter /spawn/
    """
  And a file named "external_exit.rb" with:
    """
    require "simplecov"
    SimpleCov.start
    SimpleCov.external_at_exit = true
    require_relative "lib/subprocesses"
    Subprocesses.new.run
    SimpleCov.at_exit_behavior
    """
  When I open the coverage report generated with `bundle exec ruby external_exit.rb`
  Then I should see the groups:
    | name      | coverage | files |
    | All Files | 100.00%  | 1     |
  And the report should be based upon:
    | parent process name                 |
    | parent process name (subprocess: 1) |

  Scenario: The documentation on .simplecov_spawn
  When I open the coverage report generated with `bundle exec rspec spec/spawn_spec.rb`
  Then I should see the groups:
    | name      | coverage | files |
    | All Files | 100.00%  | 1     |
