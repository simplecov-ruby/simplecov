@test_unit @config
Feature:

  Requiring 'simplecov/no_defaults' before 'simplecov' (or setting the
  SIMPLECOV_NO_DEFAULTS environment variable) gives a clean slate: none of
  SimpleCov's default configuration is loaded. That means no default HTML
  formatter and no default filters, so nothing is dropped from the report
  and nothing is rendered unless you configure it yourself.

  See https://github.com/simplecov-ruby/simplecov/issues/217

  Background:
    Given I'm working on the project "faked_project"

  Scenario: No default formatter is loaded
    Given SimpleCov for Test/Unit is configured with:
      """
      require 'simplecov/no_defaults'

      SimpleCov.start do
        command_name "No Defaults"
      end
      """

    When I successfully run `bundle exec rake test`
    Then a directory named "coverage" should exist
    And a file named "coverage/.resultset.json" should exist
    But a file named "coverage/index.html" should not exist
    And the output should not contain "Coverage report generated"

  Scenario: No default filters are loaded
    # With no defaults, even the HTML formatter has to be required
    # explicitly — defaults.rb is what normally loads it. Without the
    # default test_frameworks filter the report keeps the test files it
    # would otherwise drop, alongside the four application files.
    Given SimpleCov for Test/Unit is configured with:
      """
      require 'simplecov/no_defaults'
      require 'simplecov/formatter/html_formatter'

      SimpleCov.start do
        formatter SimpleCov::Formatter::HTMLFormatter
        command_name "No Defaults"
      end
      """

    When I open the coverage report generated with `bundle exec rake test`
    Then I should see "6 files"
    And I should see "test/some_class_test.rb"
    And I should see "test/meta_magic_test.rb"
