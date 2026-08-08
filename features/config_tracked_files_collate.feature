@test_unit @rspec
Feature:

  Files matched by `track_files` but never loaded are simulated once, at the
  merge, rather than by every process that writes a resultset. The processes
  that ran the suite record which files they were told to track, so a separate
  `SimpleCov.collate` step still reports the ones nobody loaded even though it
  never saw the `track_files` configuration itself.

  Background:
    Given I'm working on the project "faked_project"

  # The same injection, reached through `merged_result` rather than `collate`:
  # two suites merging in-process, where the tracked files must survive the
  # merge exactly once rather than being simulated by each suite in turn.
  Scenario: two suites merged in one process
    Given SimpleCov for Test/Unit is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        track_files "lib/**/*.rb"
      end
      """
    And SimpleCov for RSpec is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        track_files "lib/**/*.rb"
      end
      """

    When I open the coverage report generated with `bundle exec rake test`
    Then I should see the source files:
      | name                                    | coverage |
      | lib/faked_project.rb                    | 100.00%  |
      | lib/faked_project/untested_class.rb     | 0.00%    |
      | lib/faked_project/some_class.rb         | 80.00%   |
      | lib/faked_project/framework_specific.rb | 75.00%   |
      | lib/faked_project/meta_magic.rb         | 100.00%  |

    When I open the coverage report generated with `bundle exec rspec spec`
    Then the report should be based upon:
      | RSpec      |
      | Unit Tests |

    And I should see the groups:
      | name      | coverage | files |
      | All Files | 79.16%   | 5     |

    And I should see the source files:
      | name                                    | coverage |
      | lib/faked_project.rb                    | 100.00%  |
      | lib/faked_project/untested_class.rb     | 0.00%    |
      | lib/faked_project/some_class.rb         | 80.00%   |
      | lib/faked_project/framework_specific.rb | 87.50%   |
      | lib/faked_project/meta_magic.rb         | 100.00%  |

  Scenario: resultsets merged by a separate collate step
    Given SimpleCov for Test/Unit is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        track_files "lib/**/*.rb"
      end
      """

    When I successfully run `bundle exec rake part1`
    Then a coverage report should have been generated
    When I successfully run `mv coverage/.resultset.json coverage/resultset1.json`
    And I successfully run `rm coverage/index.html`

    When I successfully run `bundle exec rake part2`
    Then a coverage report should have been generated
    When I successfully run `mv coverage/.resultset.json coverage/resultset2.json`
    And I successfully run `rm coverage/index.html`

    # The `collate` rake task calls `SimpleCov.collate` with no configuration
    # block, and the project has no `.simplecov`, so this process knows nothing
    # about `track_files`. untested_class.rb reaches the report only because the
    # resultsets carry the paths their processes were told to track.
    When I open the coverage report generated with `bundle exec rake collate`
    Then I should see the groups:
      | name      | coverage | files |
      | All Files | 77.08%   | 5     |

    And I should see the source files:
      | name                                    | coverage |
      | lib/faked_project.rb                    | 100.00%  |
      | lib/faked_project/untested_class.rb     | 0.00%    |
      | lib/faked_project/some_class.rb         | 80.00%   |
      | lib/faked_project/framework_specific.rb | 75.00%   |
      | lib/faked_project/meta_magic.rb         | 100.00%  |
