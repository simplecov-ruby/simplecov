Feature:

  Running unit tests without simplecov configuration

  Scenario: No config at all
    Given I cd to "project"
      
    When I successfully run `bundle exec rake test`
    Then no coverage report should have been generated
    
  Scenario: Configured, but not started
    Given I cd to "project"
    Given a file named "test/simplecov_config.rb" with:
      """
      require 'simplecov'
      SimpleCov.configure do
        add_filter 'somefilter'
      end
      """

    When I successfully run `bundle exec rake test`
    Then no coverage report should have been generated