@test_unit
Feature:

  Simply adding the basic simplecov lines to a project should get
  the user a coverage report after running `rake test`

  Background:
    Given I'm working on the project "faked_project"

  Scenario:
    Given SimpleCov for Test/Unit is configured with:
      """
      require 'simplecov'
      SimpleCov.start
      """

    When I open the coverage report generated with `bundle exec rake test`
    Then I should see the groups:
      | name      | coverage | files |
      | All Files | 88.09%   | 4     |

    And I should see the source files:
      | name                                    | coverage |
      | lib/faked_project.rb                    | 100.00%  |
      | lib/faked_project/some_class.rb         | 80.00%   |
      | lib/faked_project/framework_specific.rb | 75.00%   |
      | lib/faked_project/meta_magic.rb         | 100.00%  |

      # test/* files are filtered out by the default test_frameworks profile.

    And the report should be based upon:
      | Unit Tests |
