@test_unit @config
Feature:

  Exit code should be non-zero if the coverage of any one file is below the configured value.

  Background:
    Given I'm working on the project "faked_project"

  Scenario: slightly under minimum coverage by file
    Given SimpleCov for Test/Unit is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        minimum_coverage_by_file 75.01
      end
      """

    When I run `bundle exec rake test`
    Then the exit status should not be 0
    And the output should contain "Line coverage by file (75.00%) is below the expected minimum coverage (75.01%)."
    And the output should contain "SimpleCov failed with exit 2"

  Scenario: Just passing it
    Given SimpleCov for Test/Unit is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        minimum_coverage_by_file 75
      end
      """

    When I run `bundle exec rake test`
    Then the exit status should be 0

  @branch_coverage
  Scenario: Works together with branch coverage and the new criterion announcing both failures
    Given SimpleCov for Test/Unit is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        enable_coverage :branch
        minimum_coverage_by_file line: 90, branch: 70
      end
      """

    When I run `bundle exec rake test`
    Then the exit status should not be 0
    And the output should contain "Line coverage by file (80.00%) is below the expected minimum coverage (90.00%)."
    And the output should contain "Branch coverage by file (50.00%) is below the expected minimum coverage (70.00%)."
    And the output should contain "SimpleCov failed with exit 2"

  @branch_coverage
  Scenario: Can set branch as primary coverage and it will fail if branch is below minimum coverage
    Given SimpleCov for Test/Unit is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        enable_coverage :branch
        primary_coverage :branch
        minimum_coverage_by_file 70
      end
      """

    When I run `bundle exec rake test`
    Then the exit status should not be 0
    And the output should contain "Branch coverage by file (50.00%) is below the expected minimum coverage (70.00%)."
    And the output should contain "SimpleCov failed with exit 2"
