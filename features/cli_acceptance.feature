@rspec

Feature:
  The acceptance testing for CLI process as described in #853.

  Scenario:
    Given I'm working on the project "cli_acceptance"
    When I open the coverage report generated with `bundle exec rspec spec`
    Then I should see the source files:
    | name                  | coverage |
    | lib/cli_acceptance.rb | 87.50 %  |
