@parallel_tests_project

@rspec
Feature:

  Parallel tests and its corresponding test project work together
  with Simplecov just fine

  Scenario:
    When I install dependencies
    When I open the coverage report generated with `bundle exec parallel_rspec spec`
    Then I should see the groups:
      | name      | coverage | files |
      | All Files | 89.36%   | 9     |
