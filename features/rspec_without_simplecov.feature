@rspec
Feature:

  Running specs without simplecov configuration

  Background:
    Given I cd to "project"

  Scenario: No config at all
    When I successfully run `bundle exec rspec spec`
    Then no coverage report should have been generated

  Scenario: Configured, but not started
    Given a file named "spec/simplecov_config.rb" with:
      """
      require 'simplecov'
      SimpleCov.configure do
        add_filter 'somefilter'
      end
      """

    When I successfully run `bundle exec rspec spec`
    Then no coverage report should have been generated
