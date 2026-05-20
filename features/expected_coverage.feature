@test_unit @config
Feature:

  Exit code should be non-zero if the overall coverage is either above
  or below the expected_coverage threshold. Useful for pinning coverage
  to an exact value so unexpected improvements (which should bump the
  threshold) don't slip through silently. See issue #187.

  Background:
    Given I'm working on the project "faked_project"

  Scenario: expected_coverage passes when the actual coverage matches exactly
    Given SimpleCov for Test/Unit is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        expected_coverage 88.09
      end
      """

    When I run `bundle exec rake test`
    Then the exit status should be 0

  Scenario: expected_coverage fails when actual coverage is below
    Given SimpleCov for Test/Unit is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        expected_coverage 90
      end
      """

    When I run `bundle exec rake test`
    Then the exit status should not be 0
    And the output should contain "Line coverage (88.09%) is below the expected minimum coverage (90.00%)."
    And the output should contain "SimpleCov failed with exit 2"

  Scenario: expected_coverage fails when actual coverage is above
    Given SimpleCov for Test/Unit is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        expected_coverage 80
      end
      """

    When I run `bundle exec rake test`
    Then the exit status should not be 0
    And the output should contain "Line coverage (88.09%) is above the expected maximum coverage (80.00%)."
    And the output should contain "Time to bump the threshold!"
    And the output should contain "SimpleCov failed with exit 4"

  Scenario: maximum_coverage on its own fails when actual is above
    Given SimpleCov for Test/Unit is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        maximum_coverage 85
      end
      """

    When I run `bundle exec rake test`
    Then the exit status should not be 0
    And the output should contain "Line coverage (88.09%) is above the expected maximum coverage (85.00%)."
    And the output should contain "SimpleCov failed with exit 4"
