# deactivating on JRuby due to https://github.com/jruby/jruby/issues/8200
@rspec @no_jruby
Feature:

  Running SimpleCov with verbosity enabled does not yield warnings.

  Background:
    Given I'm working on the project "faked_project"

  Scenario:
    Given SimpleCov for RSpec is configured with:
      """
      require 'simplecov'
      SimpleCov.start
      """

    When I successfully run `bundle exec rspec --warnings spec`
    Then a coverage report should have been generated
    And the output should not contain "warning"
