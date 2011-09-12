@test_unit @config
Feature:

  SimpleCov guesses the project name from the project root dir's name.
  If this is not sufficient for you, you can specify a custom name using
  SimpleCov.project_name('xyz')

  Background:
    Given I cd to "project"

  Scenario: Guessed name
    Given a file named "test/simplecov_config.rb" with:
      """
      require 'simplecov'
      SimpleCov.start
      """

    When I open the coverage report generated with `bundle exec rake test`
    Then I should see "Code coverage for Project"

  Scenario: Custom name
    Given a file named "test/simplecov_config.rb" with:
      """
      require 'simplecov'
      SimpleCov.start { project_name "Superfancy 2.0" }
      """

    When I open the coverage report generated with `bundle exec rake test`
    Then I should see "Code coverage for Superfancy 2.0"
