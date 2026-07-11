@rspec @disable-bundler

Feature:

  Parallel tests and its corresponding test project work together with Simplecov
  just fine and they produce the same output like a normal rspec run.

  # `-n 2` pins the worker count so it matches the number of spec files. Left
  # to default, parallel_rspec spawns one worker per core, and on a machine
  # with more cores than files the extra workers get nothing and write no
  # resultset. SimpleCov copes with that now, but pinning keeps the run fast
  # and deterministic across machines.

  Background:
    Given I'm working on the project "parallel_tests"

  Scenario: Running it through parallel_tests produces the same results as a normal rspec run
    Given I install dependencies
    And SimpleCov for RSpec is configured with:
      """
      require 'simplecov'
      SimpleCov.start
      """
    When I open the coverage report generated with `bundle exec parallel_rspec -n 2 spec`
    Then I should see the line coverage results for the parallel tests project

  # Note it's better not to test this in the same scenario as before.
  # Merging of results might kick in and ruin this.
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
    When I open the coverage report generated with `bundle exec parallel_rspec -n 2 spec`
    Then I should see the branch coverage results for the parallel tests project

  Scenario: Coverage violations aren't printed until the end
    Given I install dependencies
    And SimpleCov for RSpec is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        minimum_coverage 81.48
      end
      """
    When I successfully run `bundle exec parallel_rspec -n 2 spec`
    Then the output should not match /.*cover.+below.+minimum/

  # Reproduces galtzo-floss/turbo_tests2#15: worker output should not include
  # partial-result threshold failures when an explicit collate step owns the
  # final coverage report.
  Scenario: Turbo-style external collation does not print worker coverage violations
    Given I install dependencies
    And SimpleCov for RSpec is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        minimum_coverage 81.48
        coverage_dir File.join("coverage", "turbo_tests", ENV.fetch("TEST_ENV_NUMBER"))
        command_name "rspec-#{ENV.fetch("TEST_ENV_NUMBER")}"
      end
      """
    When I successfully run `env TEST_ENV_NUMBER=1 PARALLEL_TEST_GROUPS=2 bundle exec rspec spec/a_spec.rb spec/b_spec.rb`
    Then the output should not contain "SimpleCov failed with exit 2"
    And the output should not match /.*cover.+below.+minimum/
    When I successfully run `env TEST_ENV_NUMBER=2 PARALLEL_TEST_GROUPS=2 bundle exec rspec spec/c_spec.rb spec/d_spec.rb`
    Then the output should not contain "SimpleCov failed with exit 2"
    And the output should not match /.*cover.+below.+minimum/
    When I successfully run `bundle exec ruby -rsimplecov -e 'SimpleCov.collate(Dir["coverage/turbo_tests/*/.resultset.json"]) { minimum_coverage 81.48 }'`
    Then the output should contain "Coverage report generated"
    And the output should not contain "SimpleCov failed with exit 2"
