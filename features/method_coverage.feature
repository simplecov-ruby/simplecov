@rspec @method_coverage
Feature:

  Simply executing method coverage gives ok results.

  Background:
    Given I'm working on the project "faked_project"

  Scenario:
    Given SimpleCov for RSpec is configured with:
      """
      require 'simplecov'

      SimpleCov.start do
        enable_coverage :method
      end
      """
    When I open the coverage report generated with `bundle exec rspec spec`
    Then I should see the groups:
      | name      | coverage | files |
      | All Files | 91.8%    | 7     |
    And I should see a line coverage summary of 56/61
    And I should see a method coverage summary of 10/13
    And I should see the source files:
      | name                                    | coverage | method coverage |
      | lib/faked_project.rb                    | 100.00 % | 100.00 %        |
      | lib/faked_project/some_class.rb         | 80.00 %  | 75.00 %         |
      | lib/faked_project/framework_specific.rb | 75.00 %  | 33.33 %         |
      | lib/faked_project/meta_magic.rb         | 100.00 % | 100.00 %        |
      | spec/forking_spec.rb                    | 100.00 % | 100.00 %        |
      | spec/meta_magic_spec.rb                 | 100.00 % | 100.00 %        |
      | spec/some_class_spec.rb                 | 100.00 % | 100.00 %        |

    When I open the detailed view for "lib/faked_project/framework_specific.rb"
    Then I should see a line coverage summary of 6/8 for the file
    And I should see a method coverage summary of 1/3 for the file
    And I should see missed methods list:
    | name                                 |
    | #<Class:FrameworkSpecific>#test_unit |
    | #<Class:FrameworkSpecific>#cucumber  |
