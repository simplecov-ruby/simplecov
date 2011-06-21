Feature:

  Simply adding the basic simplecov lines to a project should get 
  the user a coverage report

  Scenario: 
    Given I cd to "project"
    Given a file named "test/test_helper.rb" with:
      """
      require 'rubygems'
      require 'bundler/setup'
      
      require 'simplecov'
      SimpleCov.start
      
      require 'faked_project'
      require 'test/unit'

      class Test::Unit::TestCase
      end
      """
    When I successfully run "bundle exec rake test"
    Then the stdout should contain "Coverage report generated for Unit Tests"
    And the following files should exist:
      | coverage/index.html    |
      | coverage/resultset.yml |