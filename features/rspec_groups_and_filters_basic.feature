@rspec
Feature:

  Defining some groups and filters should give a corresponding
  coverage report that respects those settings after running rspec

  Background:
    Given I'm working on the project "faked_project"

  Scenario:
    Given SimpleCov for RSpec is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        add_group 'Libs', 'lib/faked_project/'
        add_filter '/spec/'
      end
      """

    When I open the coverage report generated with `bundle exec rspec spec`
    And I should see the groups:
      | name      | coverage | files |
      | All Files | 88.09%   | 4     |
      | Libs      | 86.11%   | 3     |
      | Ungrouped | 100.00%  | 1     |

    And I should see the source files:
      | name                                    | coverage |
      | lib/faked_project.rb                    | 100.00%  |
      | lib/faked_project/some_class.rb         | 80.00%   |
      | lib/faked_project/framework_specific.rb | 75.00%   |
      | lib/faked_project/meta_magic.rb         | 100.00%  |

    When I sort the "All Files" group by "File Name" 2 times
    And I sort the "Libs" group by "File Name" 1 time
    Then the visible source files should be ordered:
      | lib/faked_project/framework_specific.rb |
      | lib/faked_project/meta_magic.rb         |
      | lib/faked_project/some_class.rb         |
    And the visible "File Name" header should be sorted ascending
