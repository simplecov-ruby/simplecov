@rspec

Feature:

  We've experienced some problems given source file encoding.
  We want to make sure we try the appropriate encoding and
  can display it correcty in the formatter.

  Background:
    Given I'm working on the project "encodings"

  Scenario: Running tests produces coverage and it's mostly legible
  When I open the coverage report generated with `bundle exec rspec spec`
  Then I should see the groups:
    | name      | coverage | files |
    | All Files | 55.56%   | 4     |

  When I open the detailed view for "lib/utf8.rb"
  Then "�" should not be visible
  And "🇯🇵" should be visible
  And "おはよう" should be visible


  When I close the detailed view
  And I open the detailed view for "lib/euc_jp.rb"
  Then "�" should not be visible
  And "おはよう" should be visible

  When I close the detailed view
  And I open the detailed view for "lib/euc_jp_not_declared.rb"
  Then "�" should not be visible
  And "Fun3" should be visible

  When I close the detailed view
  And I open the detailed view for "lib/euc_jp_not_declared_tracked.rb"
  # no way around it I guess
  Then "�" should be visible
  And "NoDeclare" should be visible
