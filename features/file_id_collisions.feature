@rspec
Feature: Source file links with colliding hashes

  Background:
    Given I'm working on the project "faked_project"

  Scenario: Every source link opens its own file
    Given SimpleCov for RSpec is configured with:
      """
      require 'simplecov'
      SimpleCov.start
      """
    And a file named "lib/file_46276.rb" with:
      """
      module File46276
        VALUE = 46_276
      end
      """
    And a file named "lib/file_56865.rb" with:
      """
      module File56865
        VALUE = 56_865
      end
      """
    And a file named "spec/file_id_collisions_spec.rb" with:
      """
      require 'spec_helper'
      require_relative '../lib/file_46276'
      require_relative '../lib/file_56865'

      RSpec.describe 'source files with colliding hashes' do
        it 'loads both files' do
          expect(File46276::VALUE + File56865::VALUE).to eq(103_141)
        end
      end
      """

    When I open the coverage report generated with `bundle exec rspec spec/file_id_collisions_spec.rb`
    And I open the detailed view for "lib/file_46276.rb"
    And I close the detailed view
    Then I open the detailed view for "lib/file_56865.rb"
