Feature:

  Simply adding the basic simplecov lines to a project should get 
  the user a coverage report

  Scenario:
    Given I cd to "project"
    Given a file named "test/simplecov_config.rb" with:
      """
      require 'simplecov'
      SimpleCov.start
      """
      
    When I successfully run `bundle exec rake test`
    Then a coverage report should have been generated

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