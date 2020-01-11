@parallel_tests_project
@rspec

Feature:

  Parallel tests and its corresponding test project work together with Simplecov
  just fine and they produce the same output like a normal rspec run.

  Scenario: Running it through parallel_tests produces the same results as a normal rspec run
    Given I install dependencies
    When I open the coverage report generated with `bundle exec parallel_rspec spec`
    Then I should see the results for the parallel tests project

  # Note it's better not to do them in the same scenario as
  # then merging of results might kick in
  Scenario: Running the project with normal rspec
    Given I install dependencies
    When I open the coverage report generated with `bundle exec rspec spec`
    Then I should see the results for the parallel tests project
