@rspec @disable-bundler

Feature:

  Parallel tests and its corresponding test project work together with Simplecov
  just fine and they produce the same output like a normal rspec run.

  Background:
    Given I'm working on the project "parallel_tests"

  # see #815
  @wip
  Scenario: Running it through parallel_tests produces the same results as a normal rspec run
    Given I install dependencies
    And SimpleCov for RSpec is configured with:
      """
      require 'simplecov'
      SimpleCov.start
      """
    When I open the coverage report generated with `bundle exec parallel_rspec spec`
    Then I should see the line coverage results for the parallel tests project

  # Note it's better not to do them in the same scenario as
  # then merging of results might kick in
  Scenario: Running the project with normal rspec
    Given I install dependencies
    And SimpleCov for RSpec is configured with:
      """
      require 'simplecov'
      SimpleCov.start
      """
    When I open the coverage report generated with `bundle exec rspec spec`
    Then I should see the line coverage results for the parallel tests project

  @branch_coverage
  Scenario: Running the project with normal rspec and branch coverage
    Given I install dependencies
    And SimpleCov for RSpec is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        enable_coverage :branch
      end
      """
    When I open the coverage report generated with `bundle exec rspec spec`
    Then I should see the branch coverage results for the parallel tests project

  # see #815
  @wip
  @branch_coverage
  Scenario: Running the project with normal rspec and branch coverage
    Given I install dependencies
    And SimpleCov for RSpec is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        enable_coverage :branch
      end
      """
    When I open the coverage report generated with `bundle exec parallel_rspec spec`
    Then I should see the branch coverage results for the parallel tests project
