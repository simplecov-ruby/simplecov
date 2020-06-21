@rspec @disable-bundler

Feature:

  The root of the project can be customized.

  Background:
    Given I'm working on the project "monorepo"

  Scenario: A coverage result is considered if it falls inside the root of the project
    Given I install dependencies
    And a file named ".simplecov" with:
      """
      SimpleCov.start do
        root __dir__
      end
      """
    When I open the coverage report generated with `bin/rspec_binstub_that_chdirs extra/spec/extra_spec.rb`
    Then I should see the groups:
      | name      | coverage | files |
      | All Files | 100.0%   | 2     |

    And I should see the source files:
      | name                        | coverage |
      | base/lib/monorepo/base.rb   | 100.00 % |
      | extra/lib/monorepo/extra.rb | 100.00 % |
