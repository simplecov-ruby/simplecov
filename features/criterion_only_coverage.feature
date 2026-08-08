@rspec
Feature: HTML reports without line coverage

  Background:
    Given I'm working on the project "faked_project"

  @branch_coverage
  Scenario: Reporting branch coverage only
    Given SimpleCov for RSpec is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        disable_coverage :line
        enable_coverage :branch
        primary_coverage :branch
      end
      """
    When I open the coverage report generated with `bundle exec rspec spec`
    Then the output should not contain "Line coverage:"
    And the output should contain "Branch coverage: 1 / 2 (50.00%)"
    And I should see the groups:
      | name      | coverage | files |
      | All Files | 50.00%   | 4     |
    And "LINE COVERAGE" should not be visible
    And "BRANCH COVERAGE" should be visible
    And I should see the source files:
      | name                                    | branch coverage |
      | lib/faked_project.rb                    | 100.00%         |
      | lib/faked_project/some_class.rb         | 50.00%          |
      | lib/faked_project/framework_specific.rb | 100.00%         |
      | lib/faked_project/meta_magic.rb         | 100.00%         |
    And I should see a branch coverage summary of 1/2

    When I open the detailed view for "lib/faked_project/some_class.rb"
    Then "Line coverage: disabled" should be visible
    And I should see a branch coverage summary of 1/2 for the file
    And I should see coverage branch data like "else: 0"

  @method_coverage
  Scenario: Reporting method coverage only
    Given SimpleCov for RSpec is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        disable_coverage :line
        enable_coverage :method
        primary_coverage :method
      end
      """
    When I open the coverage report generated with `bundle exec rspec spec`
    Then the output should not contain "Line coverage:"
    And the output should contain "Method coverage: 9 / 12 (75.00%)"
    And I should see the groups:
      | name      | coverage | files |
      | All Files | 75.00%   | 4     |
    And "LINE COVERAGE" should not be visible
    And "METHOD COVERAGE" should be visible
    And I should see the source files:
      | name                                    | method coverage |
      | lib/faked_project.rb                    | 100.00%         |
      | lib/faked_project/some_class.rb         | 75.00%          |
      | lib/faked_project/framework_specific.rb | 33.33%          |
      | lib/faked_project/meta_magic.rb         | 100.00%         |
    And I should see a method coverage summary of 9/12

    When I open the detailed view for "lib/faked_project/some_class.rb"
    Then "Line coverage: disabled" should be visible
    And I should see a method coverage summary of 3/4 for the file
