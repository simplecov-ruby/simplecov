@rspec
Feature:

  Using the setting `tracked_files` should classify whether lines
  are relevant or not (such as whitespace or comments).

  Scenario:
    Given SimpleCov for RSpec is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        track_files "lib/**/*.rb"
      end
      """
    Given a file named "lib/not_loaded.rb" with:
    """
    # A comment line. Plus a whitespace line below:

    # :nocov:
    def ignore_me
    end
    # :nocov:

    def this_is_relevant
      puts "still relevant"
    end
    """

    When I open the coverage report generated with `bundle exec rspec spec`
    Then I follow "lib/not_loaded.rb"
    Then I should see "3 relevant lines" within ".highlighted"
