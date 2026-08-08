@rspec
Feature: Sophisticated grouping and filtering on RSpec

  Defining groups and filters can be done by passing blocks or strings.
  Blocks get each SimpleCov::SourceFile instance passed an can use arbitrary
  and potentially weird conditions to remove files from the report or add them
  to specific groups.

  Background:
    Given I'm working on the project "faked_project"

  Scenario:
    Given SimpleCov for RSpec is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        add_group 'By block' do |src_file|
          src_file.filename =~ /MaGiC/i
        end
        add_group 'By string', 'faked_project/meta_magic'
        add_group 'By array', ['faked_project/meta_magic']

        add_filter 'faked_project.rb'
        # Remove all files that include "describe" in their source
        add_filter {|src_file| src_file.lines.any? {|line| line.src =~ /describe/ } }
        add_filter {|src_file| src_file.covered_percent < 100 }
      end
      """

    When I open the coverage report generated with `bundle exec rspec spec`
    Then I should see the groups:
      | name      | coverage | files |
      | All Files | 100.00%  | 1     |
      | By block  | 100.00%  | 1     |
      | By string | 100.00%  | 1     |
      | By array  | 100.00%  | 1     |

    And I should see the source files:
      | name                            | coverage |
      | lib/faked_project/meta_magic.rb | 100.00%  |

  # Regression for #1038 and the encoder's escape-delimiter collision: group
  # names must remain distinct both when punctuation differs and when one name
  # contains the literal hexadecimal spelling used to escape another. The
  # built-in All Files section must also stay separate from a configured group
  # that shares its display label.
  Scenario: Encoded group names get distinct HTML containers
    Given SimpleCov for RSpec is configured with:
      """
      require 'simplecov'
      SimpleCov.start do
        add_group '<group' do |src_file|
          src_file.filename =~ /MaGiC/i
        end
        add_group '>group' do |src_file|
          src_file.filename =~ /framework_specific/i
        end
        add_group 'By/group' do |src_file|
          src_file.filename =~ /MaGiC/i
        end
        add_group 'By_2f_group' do |src_file|
          src_file.filename =~ /framework_specific/i
        end
        add_group 'All Files' do |src_file|
          src_file.filename =~ /framework_specific/i
        end

        add_filter 'faked_project.rb'
        add_filter {|src_file| src_file.lines.any? {|line| line.src =~ /describe/ } }
        add_filter {|src_file| src_file.covered_percent < 100 }
      end
      """

    When I open the coverage report generated with `bundle exec rspec spec`
    Then I should see the groups:
      | name      | coverage | files |
      | All Files | 100.00%  | 1     |
      | <group    | 100.00%  | 1     |
      | >group    | 100.00%  | 0     |
      | By/group  | 100.00%  | 1     |
      | By_2f_group | 100.00%  | 0     |
      | All Files | 100.00%  | 0     |

    And each group tab should open its own file list
