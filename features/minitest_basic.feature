Feature:

  Scenario:
    Given SimpleCov for Minitest is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        add_filter "test_helper.rb"
      end
      """

    When I open the coverage report generated with `bundle exec rake minitest`
    Then I should see the groups:
      | name      | coverage | files |
      | All Files | 87.5%   | 2     |

    And I should see the source files:
      | name                                    | coverage |
      | lib/faked_project/some_class.rb         | 80.0 %   |
      | minitest/some_test.rb                   | 100.0 %  |

  Scenario:
    Given SimpleCov for Minitest is configured with:
      """
      require 'simplecov'
      SimpleCov.start
      """

    When I open the coverage report generated with `bundle exec ruby -Ilib:minitest minitest/other_test.rb`
    Then I should see the groups:
      | name      | coverage | files |
      | All Files | 80.0%    | 1     |

    And I should see the source files:
      | name                                    | coverage |
      | lib/faked_project/some_class.rb         | 80.0 %   |
