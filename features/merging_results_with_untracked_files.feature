@test_unit @rspec @merging
Feature:

  When merging two test suites, a file may not be loaded by one of them
  but loaded by the other. When this happens, the merged result should
  discard the zeroes from the former suite and use the information of the
  second.

  Scenario:
    Given SimpleCov for Test/Unit is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        add_filter 'spec.rb'
        track_files "lib/**/*.rb"
      end
      """
    And SimpleCov for RSpec is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        add_filter 'spec.rb'
        track_files "lib/**/*.rb"
      end
      """

    And a file named "spec/faked_project/another_class_spec.rb" with:
      """
      # encoding: UTF-8
      require "spec_helper"
      require "faked_project/untested_class"

      describe UntestedClass do
        # TODO
      end
      """

    When I open the coverage report generated with `bundle exec rake test`
    Then the line count per file should be distributed as follows:
      | name                                | never | covered | skipped | missed |
      | lib/faked_project/untested_class.rb | 0     | 0       | 0       | 11     |

    When I open the coverage report generated with `bundle exec rspec spec`
    Then the line count per file should be distributed as follows:
      | name                                | never | covered | skipped | missed |
      | lib/faked_project/untested_class.rb | 8     | 2       | 0       | 1      |
