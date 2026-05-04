@test_unit @nocov
Feature:

  When code is wrapped in `# simplecov:disable` / `# simplecov:enable`
  comment blocks (or trailed by an inline `# simplecov:disable`), it does
  not count against the coverage numbers.

  Background:
    Given I'm working on the project "faked_project"
    Given SimpleCov for Test/Unit is configured with:
      """
      require 'simplecov'
      SimpleCov.start 'test_frameworks'
      """

  Scenario: Block disable of line coverage
    Given a file named "lib/faked_project/directive.rb" with:
      """
      class SourceCodeWithDirective
        # simplecov:disable line
        def some_weird_code
          never_reached
        rescue => err
          but no one cares about invalid ruby here
        end
        # simplecov:enable line
      end
      """

    When I open the coverage report generated with `bundle exec rake test`

    Then I should see the source files:
      | name                                    | coverage |
      | lib/faked_project.rb                    | 100.00%  |
      | lib/faked_project/some_class.rb         | 80.00%   |
      | lib/faked_project/framework_specific.rb | 75.00%   |
      | lib/faked_project/meta_magic.rb         | 100.00%  |
      | lib/faked_project/directive.rb          | 100.00%  |

    And there should be 7 skipped lines in the source files

  Scenario: Inline disable of a single line
    Given a file named "lib/faked_project/directive.rb" with:
      """
      class SourceCodeWithDirective
        def boom(value)
          value || raise("absurd") # simplecov:disable
        end
      end
      """

    When I open the coverage report generated with `bundle exec rake test`

    Then I should see the source files:
      | name                                    | coverage |
      | lib/faked_project.rb                    | 100.00%  |
      | lib/faked_project/some_class.rb         | 80.00%   |
      | lib/faked_project/framework_specific.rb | 75.00%   |
      | lib/faked_project/meta_magic.rb         | 100.00%  |
      | lib/faked_project/directive.rb          | 100.00%  |

    And there should be 1 skipped lines in the source files

  Scenario: Block disable with a free-form trailing reason
    Given a file named "lib/faked_project/directive.rb" with:
      """
      class SourceCodeWithDirective
        # simplecov:disable line legacy adapter, scheduled for removal
        def some_weird_code
          never_reached
        rescue => err
          but no one cares about invalid ruby here
        end
        # simplecov:enable line
      end
      """

    When I open the coverage report generated with `bundle exec rake test`

    Then I should see the source files:
      | name                                    | coverage |
      | lib/faked_project.rb                    | 100.00%  |
      | lib/faked_project/some_class.rb         | 80.00%   |
      | lib/faked_project/framework_specific.rb | 75.00%   |
      | lib/faked_project/meta_magic.rb         | 100.00%  |
      | lib/faked_project/directive.rb          | 100.00%  |

    And there should be 7 skipped lines in the source files

  Scenario: Directive markers inside string literals are ignored
    Given a file named "lib/faked_project/directive.rb" with:
      """
      class SourceCodeWithDirective
        BANNER = "# simplecov:disable"
        def message
          BANNER
        end
      end
      """

    When I open the coverage report generated with `bundle exec rake test`

    Then there should be 0 skipped lines in the source files
