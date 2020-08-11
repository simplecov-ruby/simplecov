@rspec
Feature:

  RSpec failing in different ways results SimpleCov saying something beforehand. However it doesn't identify itself as the originator of said error.

  Background:
    Given I'm working on the project "faked_project"

  Scenario:
    When I run `bundle exec rspec bad_spec/failing_spec.rb`
    Then the exit status should not be 0
    And the output should match /SimpleCov.+previous.+error/
    And the output should not match /SimpleCov.+exit.+with.+status/

  Scenario:
    When I run `bundle exec rspec bad_spec/fail_with_5.rb`
    Then the exit status should be 5
    And the output should match /SimpleCov.+previous.+error/
    And the output should not match /SimpleCov.+exit.+with.+status/
