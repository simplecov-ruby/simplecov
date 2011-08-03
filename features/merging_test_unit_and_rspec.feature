@test_unit @rspec
Feature:

  Test suites like RSpec and Test/Unit should be merged automatically
  when both have been run recently. The coverage report will feature
  the joined results of all test suites that are using SimpleCov.

  Scenario:
    Given I cd to "project"
    Given a file named "test/simplecov_config.rb" with:
      """
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        add_filter 'spec.rb'
      end
      """
    And a file named "spec/simplecov_config.rb" with:
      """
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        add_filter 'spec.rb'
      end
      """
      
    When I successfully run `bundle exec rake test`
    Then a coverage report should have been generated
    
    When I successfully run `bundle exec rspec spec`
    Then a coverage report should have been generated

    Given I open the coverage report
    Then I should see the groups:
      | name      | coverage | files |
      | All Files | 92.31%   | 4     |
      
    And I should see the source files:
      | name                                      | coverage |
      | ./lib/faked_project.rb                    | 100.0 %  |
      | ./lib/faked_project/some_class.rb         | 81.82 %  |
      | ./lib/faked_project/framework_specific.rb |  87.5 %  |
      | ./lib/faked_project/meta_magic.rb         | 100.0 %  |