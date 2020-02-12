@cucumber
Feature:

  Simply adding the basic simplecov lines to a project should get
  the user a coverage report after running `cucumber features`

  Background:
    Given I'm working on the project "faked_project"

  Scenario:
    Given SimpleCov for Cucumber is configured with:
      """
      require 'simplecov'
      SimpleCov.start
      """

    When I open the coverage report generated with `bundle exec cucumber features`
    Then I should see the groups:
      | name      | coverage | files |
      | All Files | 91.23%   | 6     |

    And I should see the source files:
      | name                                    | coverage |
      | lib/faked_project.rb                    | 100.00 %  |
      | lib/faked_project/some_class.rb         | 80.00 %   |
      | lib/faked_project/framework_specific.rb | 75.00 %   |
      | lib/faked_project/meta_magic.rb         | 100.00 %  |
      | features/step_definitions/my_steps.rb   | 100.00 %  |
      | features/support/simplecov_config.rb    | 100.00 %  |

    And the report should be based upon:
      | Cucumber Features |
