@rspec @disable-bundler @process_fork

Feature:

  rspec-conductor is a queue-based parallel spec runner. It forks its workers
  from a server process, gives each worker one spec file at a time, and marks
  every worker with the parallel_tests environment convention: TEST_ENV_NUMBER
  per worker plus PARALLEL_TEST_GROUPS for the worker count (since
  rspec-conductor 1.0.7). SimpleCov's generic parallel adapter picks that up
  without any configuration, so each worker records under a unique suite name
  and the first worker waits for its siblings and builds the merged report.

  # `--workers 2` pins the worker count for a fast, deterministic run. Left to
  # default, rspec-conductor spawns one worker per core. Workers that get no
  # spec file still load spec_helper at spawn and record an empty resultset,
  # so the merged totals come out the same either way.
  #
  # The scenarios assert on the generated report files rather than on the
  # usual "Coverage report generated" line. The conductor server closes each
  # worker's output pipes once the worker has sent its run summary, before
  # at_exit hooks run, so nothing SimpleCov prints from at_exit can reach
  # the output. The report itself is written fine.

  Background:
    Given I'm working on the project "parallel_tests" with the Gemfile from "rspec_conductor"

  Scenario: Running it through rspec-conductor produces the same results as a normal rspec run
    Given I install dependencies
    And SimpleCov for RSpec is configured with:
      """
      require 'simplecov'
      SimpleCov.start
      """
    When I successfully run `bundle exec rspec-conductor --workers 2 spec`
    Then the following files should exist:
      | coverage/index.html      |
      | coverage/.resultset.json |
    When I open the coverage report
    Then I should see the line coverage results for the parallel fixture project

  # In default mode the first worker's TEST_ENV_NUMBER is "" like
  # parallel_tests. With --first-is-1 it is "1" instead, and the workers count
  # 1..N. Both spellings must resolve to a single reporting worker.
  Scenario: Running with --first-is-1 merges just the same
    Given I install dependencies
    And SimpleCov for RSpec is configured with:
      """
      require 'simplecov'
      SimpleCov.start
      """
    When I successfully run `bundle exec rspec-conductor --workers 2 --first-is-1 spec`
    Then the following files should exist:
      | coverage/index.html      |
      | coverage/.resultset.json |
    When I open the coverage report
    Then I should see the line coverage results for the parallel fixture project

  @branch_coverage
  Scenario: Running with branch coverage enabled
    Given I install dependencies
    And SimpleCov for RSpec is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        enable_coverage :branch
      end
      """
    When I successfully run `bundle exec rspec-conductor --workers 2 spec`
    Then the following files should exist:
      | coverage/index.html      |
      | coverage/.resultset.json |
    When I open the coverage report
    Then I should see the branch coverage results for the parallel fixture project

  # Each worker on its own covers only a slice of the project, so a threshold
  # check against a single worker's partial result would fail. Only the
  # reporting worker, after merging every sibling's slice, may enforce it.
  #
  # The conductor server swallows a worker's output printed from at_exit and
  # ignores its exit status once its run summary is in, so asserting on the
  # command's output or exit code proves nothing here. Instead the scenario
  # leans on .last_run.json, which SimpleCov writes only when the threshold
  # check passes. Finding it filled with the merged 81.48 shows the check ran
  # against the merged result, where any single worker's slice would have
  # failed and left the file unwritten.
  Scenario: Coverage thresholds are enforced against the merged result, not per worker
    Given I install dependencies
    And SimpleCov for RSpec is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        minimum_coverage 81.48
      end
      """
    When I successfully run `bundle exec rspec-conductor --workers 2 spec`
    Then the file "coverage/.last_run.json" should contain "81.48"
    When I open the coverage report
    Then I should see the line coverage results for the parallel fixture project
