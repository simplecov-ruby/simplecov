Feature:

  Simply adding the basic simplecov lines to a project should get 
  the user a coverage report after running `rake test`

  Scenario:
    Given I cd to "project"
    Given a file named "test/simplecov_config.rb" with:
      """
      require 'simplecov'
      SimpleCov.start
      """
      
    When I successfully run `bundle exec rake test`
    Then a coverage report should have been generated

    Given I open the coverage report
    Then I should see the groups:
      |      name | coverage | files |
      | All Files |   95.65% |     5 |
      
    And I should see the source files:
      |                              name | coverage |
      | ./lib/faked_project.rb            |  100.0 % |
      | ./lib/faked_project/some_class.rb |  81.82 % |
      | ./lib/faked_project/meta_magic.rb |  100.0 % |
      | ./test/meta_magic_test.rb         |  100.0 % |
      | ./test/some_class_test.rb         |  100.0 % |
      
      # Note: faked_test.rb is not appearing here since that's the first unit test file
      # loaded by Rake, and only there test_helper is required, which then loads simplecov
      # and triggers tracking of all other loaded files! Solution for this would be to
      # configure simplecov in this first test instead of test_helper.