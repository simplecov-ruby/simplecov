@test_unit
Feature:

  Using SimpleCov.parallel_collate should get the user the same coverage report
  SimpleCov.collate does, with the merge fanned out across forked workers.

  Background:
    Given I'm working on the project "faked_project"

  Scenario:
    Given SimpleCov for Test/Unit is configured with:
      """
      require 'simplecov'
      SimpleCov.start
      """

    When I successfully run `bundle exec rake part1`
    Then a coverage report should have been generated
    When I successfully run `mv coverage/.resultset.json coverage/resultset1.json`
    And I successfully run `rm coverage/index.html`

    When I successfully run `bundle exec rake part2`
    Then a coverage report should have been generated
    When I successfully run `mv coverage/.resultset.json coverage/resultset2.json`
    And I successfully run `rm coverage/index.html`

    # Identical to the figures in test_unit_collate.feature: fanning the merge
    # out changes how the resultsets are folded, not what they fold to.
    When I open the coverage report generated with `bundle exec rake parallel_collate`
    Then I should see the groups:
      | name      | coverage | files |
      | All Files | 88.09%   | 4     |

    And I should see the source files:
      | name                                    | coverage |
      | lib/faked_project.rb                    | 100.00%  |
      | lib/faked_project/some_class.rb         | 80.00%   |
      | lib/faked_project/framework_specific.rb | 75.00%   |
      | lib/faked_project/meta_magic.rb         | 100.00%  |

    And the report should be based upon:
      | Unit Tests |
