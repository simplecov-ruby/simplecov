@test_unit
Feature:

  When code matches a nocov regex, it does not count against the coverage numbers

  Background:
    Given SimpleCov for Test/Unit is configured with:
      """
      require 'simplecov'
      SimpleCov.start 'test_frameworks' do
        SimpleCov.nocov_regex /^[\s]*def some_weird_code/
        SimpleCov.nocov_regex /^[\s]*never_reached/
      end
      """

  Scenario: Plain run with a nocov'd method
    Given a file named "lib/faked_project/nocov_regex.rb" with:
      """
      class SourceCodeMatchingNocovRegex
        def some_weird_code
          never_reached
        end
      end
      """

    When I open the coverage report generated with `bundle exec rake test`

    Then I should see the source files:
      | name                                    | coverage |
      | lib/faked_project.rb                    | 100.0 %  |
      | lib/faked_project/some_class.rb         | 80.0 %   |
      | lib/faked_project/framework_specific.rb | 75.0 %   |
      | lib/faked_project/meta_magic.rb         | 100.0 %  |
      | lib/faked_project/nocov_regex.rb        | 100.0 %  |

    And there should be 2 skipped lines in the source files

    And the report should be based upon:
      | Unit Tests |
