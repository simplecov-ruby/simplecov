@test_unit @config
Feature:

  Exit code should be non-zero if the overall coverage is below the
  minimum_coverage threshold.

  Background:
    Given I'm working on the project "faked_project"

  Scenario: It fails against too high coverage
    Given SimpleCov for Test/Unit is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        minimum_coverage 90
      end
      """

    When I run `bundle exec rake test`
    Then the exit status should not be 0
    And the output should contain "Line coverage (88.09%) is below the expected minimum coverage (90.00%)."
    And the output should contain "SimpleCov failed with exit 2"

  Scenario: It fails if it's just 0.01% too low
    Given SimpleCov for Test/Unit is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        minimum_coverage 88.10
      end
      """

    When I run `bundle exec rake test`
    Then the exit status should not be 0
    And the output should contain "Line coverage (88.09%) is below the expected minimum coverage (88.10%)."
    And the output should contain "SimpleCov failed with exit 2"

  Scenario: It passes when it is exactly the coverage
    Given SimpleCov for Test/Unit is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        minimum_coverage 88.09
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
        minimum_coverage line: 90, branch: 80
      end
      """

    When I run `bundle exec rake test`
    Then the exit status should not be 0
    And the output should contain "Line coverage (88.09%) is below the expected minimum coverage (90.00%)."
    And the output should contain "Branch coverage (50.00%) is below the expected minimum coverage (80.00%)."
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
        minimum_coverage 80
      end
      """

    When I run `bundle exec rake test`
    Then the exit status should not be 0
    And the output should contain "Branch coverage (50.00%) is below the expected minimum coverage (80.00%)."
    And the output should contain "SimpleCov failed with exit 2"
