@test_unit @config
Feature:

  SimpleCov::Formatter::JSONFormatter is one of the
  formatters included by default, useful for exporting
  coverage results in JSON format.

  Background:
    Given I'm working on the project "faked_project"

  Scenario: With JSONFormatter
    Given SimpleCov for Test/Unit is configured with:
      """
      require 'simplecov'
      SimpleCov.formatter = SimpleCov::Formatter::JSONFormatter
      SimpleCov.at_exit do
        puts SimpleCov.result.format!
      end
      SimpleCov.start do
        add_group 'Libs', 'lib/faked_project/'
      end
      """

    When I successfully run `bundle exec rake test`
    Then a JSON coverage report should have been generated in "coverage"
    And the output should contain "JSON Coverage report generated"
