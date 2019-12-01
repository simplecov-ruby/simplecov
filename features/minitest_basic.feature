Feature:

  Scenario:
    Given SimpleCov for Minitest is configured with:
      """
      require 'simplecov'
      SimpleCov.start
      """

    When I open the coverage report generated with `bundle exec rake minitest`
    Then I should see the groups:
      | name      | coverage | files |
      | All Files | 80.0%    | 1     |

    And I should see the source files:
      | name                                    | coverage |
      | lib/faked_project/some_class.rb         | 80.0 %   |

