@test_unit @config @adapters
Feature:

  In order to re-use SimpleCov settings across projects,
  adapters can be defined that hold configuration settings
  that can be loaded at once.

  Background:
    Given SimpleCov for Test/Unit is configured with:
      """
      require 'simplecov'
      """

  Scenario: Defining and using a custom adapter
    Given a file named ".simplecov" with:
      """
      SimpleCov.adapters.define 'custom_command' do
        command_name "Adapter Command"
      end

      SimpleCov.start do
        load_adapter 'test_frameworks'
        load_adapter 'custom_command'
      end
      """

    When I open the coverage report generated with `bundle exec rake test`
    Then I should see "4 files in total."
    And I should see "using Adapter Command" within "#footer"

  Scenario: Using existing adapter in custom adapter and supplying adapter to start command
    Given a file named ".simplecov" with:
      """
      SimpleCov.adapters.define 'my_adapter' do
        load_adapter 'test_frameworks'
        command_name "My Adapter"
      end

      SimpleCov.start 'my_adapter'
      """

    When I open the coverage report generated with `bundle exec rake test`
    Then I should see "4 files in total."
    And I should see "using My Adapter" within "#footer"
