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
      
    When I successfully run `bundle exec rake test`
    Then a coverage report should have been generated

    When I open the coverage report
    Then I should see "Code coverage for Project"
  
  Scenario: Custom name
    Given a file named "test/simplecov_config.rb" with:
      """
      require 'simplecov'
      SimpleCov.start { project_name "Superfancy 2.0" }
      """
    
    When I successfully run `bundle exec rake test`
    Then a coverage report should have been generated

    When I open the coverage report
    Then I should see "Code coverage for Superfancy 2.0"