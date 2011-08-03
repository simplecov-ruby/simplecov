Feature:

  Simply adding the basic simplecov lines to a project should get 
  the user a coverage report

  Scenario:
    Given I cd to "project"
    Given a file named "test/test_helper.rb" with:
      """
      require 'rubygems'
      require 'bundler/setup'
      
      require 'simplecov'
      SimpleCov.start
      
      require 'faked_project'
      require 'test/unit'

      class Test::Unit::TestCase
      end
      """
      
    When I successfully run `bundle exec rake test`
    Then the stdout should contain "Coverage report generated for Unit Tests"
    And the following files should exist:
      | coverage/index.html    |
      | coverage/resultset.yml |
    
    When I open the coverage report
    Then I should see the groups:
      |      name | coverage |
      | All Files |   95.65% |
      
    And I should see the source files:
      |                              name | coverage |
      | ./lib/faked_project.rb            |  100.0 % |
      | ./lib/faked_project/some_class.rb |  81.82 % |
      | ./lib/faked_project/meta_magic.rb |  100.0 % |
      | ./test/meta_magic_test.rb         |  100.0 % |
      | ./test/some_class_test.rb         |  100.0 % |