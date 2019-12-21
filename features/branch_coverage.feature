@rspec @branch_coverage
Feature:

  Simply executing branch coverage gives ok results.

  Scenario:
    Given SimpleCov for RSpec is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        coverage_criterion :branch
      end
      """
    When I open the coverage report generated with `bundle exec rspec spec`
    # note: branch coverage here still seems somewhat suspect so sbject to
    # change.
    Then I should see the groups:
      | name      | coverage | files |
      | All Files | 91.8%    | 7     |
    And I should see the source files:
      | name                                    | coverage | branch coverage |
      | lib/faked_project.rb                    | 100.0 %  | 100.0 %         |
      | lib/faked_project/some_class.rb         | 80.0 %   | 50.0 %          |
      | lib/faked_project/framework_specific.rb | 75.0 %   | 100.0 %         |
      | lib/faked_project/meta_magic.rb         | 100.0 %  | 100.0 %         |
      | spec/forking_spec.rb                    | 100.0 %  | 50.0 %          |
      | spec/meta_magic_spec.rb                 | 100.0 %  | 100.0 %         |
      | spec/some_class_spec.rb                 | 100.0 %  | 100.0 %         |
