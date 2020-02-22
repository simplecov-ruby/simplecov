@rspec

Feature:
  We don't want to have pagination.
  But it's good to have a test project that would at least trigger
  pagination for 10+ source files or so, so we can avoid nasty surprises.

  Background:
    Given I'm working on the project "pagination"

  Scenario:
    When I open the coverage report generated with `bundle exec rspec`
    Then I should see the groups:
      | name      | coverage | files |
      | All Files | 100.0%   | 12    |

    When I open the detailed view for "lib/a.rb"
    Then "nothing to see here" should be visible

    When I close the detailed view
    And I open the detailed view for "lib/l.rb"
    Then "nothing to see here" should be visible
