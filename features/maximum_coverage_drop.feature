@test_unit @config
Feature:

  Exit code should be non-zero if the overall coverage decreases by more than
  the maximum_coverage_drop threshold.

  Background:
    Given I'm working on the project "faked_project"

  Scenario: maximum_coverage_drop configured can cause spec failure
    Given SimpleCov for Test/Unit is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        maximum_coverage_drop 3.14
      end
      """

    When I run `bundle exec rake test`
    Then the exit status should be 0
    And a file named "coverage/.last_run.json" should exist

    Given a file named "lib/faked_project/missed.rb" with:
      """
      class UncoveredSourceCode
        def foo
          never_reached
        rescue => err
          but no one cares about invalid ruby here
        end
      end
      """

    When I run `bundle exec rake test`
    Then the exit status should not be 0
    And the output should contain "Line coverage has dropped by 3.31% since the last time (maximum allowed: 3.14%)."
    And a file named "coverage/.last_run.json" should exist
    And the file "coverage/.last_run.json" should contain:
      """
      {
        "result": {
          "line": 88.09
        }
      }
      """

  Scenario: maximum_coverage_drop not configured updates resultset
    Given SimpleCov for Test/Unit is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
      end
      """

    When I run `bundle exec rake test`
    Then the exit status should be 0
    And a file named "coverage/.last_run.json" should exist
    And the file "coverage/.last_run.json" should contain:
      """
      {
        "result": {
          "line": 88.09
        }
      }
      """

    Given a file named "lib/faked_project/missed.rb" with:
      """
      class UncoveredSourceCode
        def foo
          never_reached
        rescue => err
          but no one cares about invalid ruby here
        end
      end
      """

    When I run `bundle exec rake test`
    Then the exit status should be 0
    And a file named "coverage/.last_run.json" should exist
    And the file "coverage/.last_run.json" should contain:
      """
      {
        "result": {
          "line": 84.78
        }
      }
      """

  Scenario: test failures do not update the resultset
    Given SimpleCov for RSpec is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        add_group 'Libs', 'lib/faked_project/'
        add_filter '/spec/'
        maximum_coverage_drop 0
      end
      """

    And a file named "lib/faked_project/missed.rb" with:
      """
      class UncoveredSourceCode
        def foo
          never_reached
        rescue => err
          but no one cares about invalid ruby here
        end
      end
      """

    And a file named "spec/failing_spec.rb" with:
      """
      require "spec_helper"
      describe FakedProject do
        it "fails" do
          expect(false).to eq(true)
        end
      end
      """
    And the file named "coverage/.last_run.json" with:
      """
      {
        "result": {
          "line": 100.0
        }
      }
      """

    When I run `bundle exec rspec spec`
    Then the exit status should be 1
    And a file named "coverage/.last_run.json" should exist
    And the file "coverage/.last_run.json" should contain:
      """
      {
        "result": {
          "line": 100.0
        }
      }
      """

  Scenario: When the previous last_run file has legacy covered_percent it still works
    Given SimpleCov for Test/Unit is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        maximum_coverage_drop 0
      end
      """
    And the file "coverage/.last_run.json" with:
      """
      {
        "result": {
          "covered_percent": 88.09
        }
      }
      """

    When I run `bundle exec rake test`
    Then the exit status should be 0
    And a file named "coverage/.last_run.json" should exist
    And the file "coverage/.last_run.json" should contain:
      """
      {
        "result": {
          "line": 88.09
        }
      }
      """

  Scenario: When the previous last_run file has covered_percent and we fail does not update it
    Given SimpleCov for RSpec is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        add_group 'Libs', 'lib/faked_project/'
        add_filter '/spec/'
        maximum_coverage_drop 0
      end
      """

    And a file named "lib/faked_project/missed.rb" with:
      """
      class UncoveredSourceCode
        def foo
          never_reached
        rescue => err
          but no one cares about invalid ruby here
        end
      end
      """

    And a file named "spec/failing_spec.rb" with:
      """
      require "spec_helper"
      describe FakedProject do
        it "fails" do
          expect(false).to eq(true)
        end
      end
      """
    And the file named "coverage/.last_run.json" with:
      """
      {
        "result": {
          "covered_percent": 100.0
        }
      }
      """

    When I run `bundle exec rspec spec`
    Then the exit status should be 1
    And a file named "coverage/.last_run.json" should exist
    And the file "coverage/.last_run.json" should contain:
      """
      {
        "result": {
          "covered_percent": 100.0
        }
      }
      """

  @branch_coverage
  Scenario: Works together with branch coverage and line coverage, announcing both failures
    Given SimpleCov for Test/Unit is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        enable_coverage :branch
        maximum_coverage_drop line: 0, branch: 0
      end
      """
    And a file named "lib/faked_project/missed.rb" with:
      """
      class UncoveredSourceCode
        def foo
          never_reached
        rescue => err
          but no one cares about invalid ruby here
        end
      end
      """

    And a file named "spec/failing_spec.rb" with:
      """
      require "spec_helper"
      describe FakedProject do
        it "fails" do
          false ? true : expect(false).to eq(true)
        end
      end
      """
    And the file named "coverage/.last_run.json" with:
      """
      {
        "result": {
          "line": 100.0,
	        "branch": 100.0
        }
      }
      """

    When I run `bundle exec rake test`
    Then the exit status should not be 0
    And the output should contain "Line coverage has dropped by 15.22% since the last time (maximum allowed: 0.00%)."
    And the output should contain "Branch coverage has dropped by 50.00% since the last time (maximum allowed: 0.00%)."
    And the output should contain "SimpleCov failed with exit 3"

  @branch_coverage
  Scenario: Can set branch as primary coverage and it will fail if branch is below maximum coverage drop
    Given SimpleCov for Test/Unit is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        enable_coverage :branch
        primary_coverage :branch
        maximum_coverage_drop 0
      end
      """
    And a file named "lib/faked_project/missed.rb" with:
      """
      class UncoveredSourceCode
        def foo
          never_reached
        rescue => err
          but no one cares about invalid ruby here
        end
      end
      """

    And a file named "spec/failing_spec.rb" with:
      """
      require "spec_helper"
      describe FakedProject do
        it "fails" do
          false ? true : expect(false).to eq(true)
        end
      end
      """
    And the file named "coverage/.last_run.json" with:
      """
      {
        "result": {
          "line": 100.0,
          "branch": 100.0
        }
      }
      """

    When I run `bundle exec rake test`
    Then the exit status should not be 0
    And the output should contain "Branch coverage has dropped by 50.00% since the last time (maximum allowed: 0.00%)."
    And the output should contain "SimpleCov failed with exit 3"

  @branch_coverage
  Scenario: Can set branch as primary coverage and it will fail if branch is below maximum coverage drop
    Given SimpleCov for Test/Unit is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        enable_coverage :branch
	      primary_coverage :branch
	      maximum_coverage_drop line: 0, branch: 0
      end
      """
    And a file named "lib/faked_project/missed.rb" with:
      """
      class UncoveredSourceCode
        def foo
          never_reached
        rescue => err
          but no one cares about invalid ruby here
        end
      end
      """

    And a file named "spec/failing_spec.rb" with:
      """
      require "spec_helper"
      describe FakedProject do
        it "fails" do
          false ? true : expect(false).to eq(true)
        end
      end
      """
    And the file named "coverage/.last_run.json" with:
      """
      {
        "result": {
          "line": 100.0,
	        "branch": 100.0
        }
      }
      """

    When I run `bundle exec rake test`
    Then the exit status should not be 0
    And the output should contain "Branch coverage has dropped by 50.00% since the last time (maximum allowed: 0.00%)."
    And the output should contain "Line coverage has dropped by 15.22% since the last time (maximum allowed: 0.00%)."
    And the output should contain "SimpleCov failed with exit 3"
