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
    | All Files | 83.33%   | 3     |

  When I open the detailed view for "lib/utf8.rb"
  Then I should not see "�"
  And I should see "🇯🇵"
  And I should see "おはよう"


  When I close the detailed view
  And I open the detailed view for "lib/euc_jp.rb"
  Then I should not see "�"
  And I should see "おはよう"

  When I close the detailed view
  And I open the detailed view for "lib/euc_jp_not_declared.rb"
  Then I should not see "�"
  And I should see "Fun3"
