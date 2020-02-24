@rspec @disable-bundler @rails6

Feature:
  Make sure that a fairly standard rspec-rails setup within a rails
  application works.

  See #873 for an example of how this might break.

  Background:
    Given I'm working on the project "rails/rspec_rails"

  Scenario: Running bundle exec rspec produces a coverage report
    Given I install dependencies
    When I open the coverage report generated with `bundle exec rspec`
    Then I should see the groups:
      | name        | coverage | files |
      | All Files   | 36.36%   | 5     |
      | Controllers | 0.0%     | 1     |
      | Channels    | 100.0%   | 0     |
      | Models      | 50.0%    | 2     |
      | Mailers     | 100.0%   | 0     |
      | Helpers     | 100.0%   | 1     |
      | Jobs        | 0.0%     | 1     |
      | Libraries   | 100.0%   | 0     |
