# frozen_string_literal: true

# Just a shortcut to make framework setup more readable
# The test project is using separate config files to avoid specifying all of
# test/spec_helper in the features every time.
Given /^SimpleCov for (.*) is configured with:$/ do |framework, config_body|
  framework_dir =
    case framework
    when /RSpec/i
      "spec"
    when %r{Test/Unit}i
      "test"
    when /Cucumber/i
      "features/support"
    when /Minitest/i
      "minitest"
    else
      raise ArgumentError, "Could not identify test framework #{framework}!"
    end

  steps %(
    Given a file named "#{framework_dir}/simplecov_config.rb" with:
      """
      #{config_body}
      """
    )
end

When /^I open the coverage report generated with `([^`]+)`$/ do |command|
  steps %(
    When I successfully run `#{command}`
    Then a coverage report should have been generated
    When I open the coverage report
    )
end

Then /^a coverage report should have been generated(?: in "([^"]*)")?$/ do |coverage_dir|
  coverage_dir ||= "coverage"
  steps %(
    Then the output should contain "Coverage report generated"
    And a directory named "#{coverage_dir}" should exist
    And the following files should exist:
      | #{coverage_dir}/index.html      |
      | #{coverage_dir}/.resultset.json |
    )
end

Then /^a JSON coverage report should have been generated(?: in "([^"]*)")?$/ do |coverage_dir|
  coverage_dir ||= "coverage"
  steps %(
    Then the output should contain "Coverage report generated"
    And a directory named "#{coverage_dir}" should exist
    And the following files should exist:
      | #{coverage_dir}/coverage.json      |
    )
end

Then /^no coverage report should have been generated(?: in "([^"]*)")?$/ do |coverage_dir|
  coverage_dir ||= "coverage"
  steps %(
    Then the output should not contain "Coverage report generated"
    And a directory named "#{coverage_dir}" should not exist
    And the following files should not exist:
      | #{coverage_dir}/index.html      |
      | #{coverage_dir}/.resultset.json |
    )
end

Then /^the report should be based upon:$/ do |table|
  frameworks = table.raw.flatten
  steps %(
    Then the output should contain "Coverage report generated for #{frameworks.join(', ')}"
    And I should see "using #{frameworks.join(', ')}" within "#footer"
    )
end

# This is necessary to ensure timing-dependant tests like the merge timeout
# do not fail on powerful machines.
When /^I wait for (\d+) seconds$/ do |seconds|
  sleep seconds.to_i
end

Then "the overlay should be open" do
  expect(page).to have_css("#source-dialog[open]")
end

When "I install dependencies" do
  # Remove lock file to avoid bundler version conflicts across Ruby versions
  in_current_directory { FileUtils.rm_f("Gemfile.lock") }
  # bundle may take its time
  steps %(
    When I successfully run `bundle` for up to 120 seconds
  )
end

When "I pry" do
  # rubocop:disable Lint/Debugger
  binding.irb
  # rubocop:enable Lint/Debugger
end

Given "I'm working on the project {string}" do |project_name|
  source = File.expand_path("../../test_projects/#{project_name}", __dir__)

  # Clean up and create blank state for project
  cd(".") do
    FileUtils.rm_rf "project"
    FileUtils.cp_r "#{source}/", "project"

    # Coverage output is gitignored, so an ad-hoc local run can leave a stray
    # `coverage/` dir in the source that cp_r then drags into the fresh sandbox,
    # breaking "no coverage report" assertions (a local-only flake — CI checks
    # out clean). Drop copied coverage dirs the source doesn't track. The
    # old_coverage_json project ships a tracked `coverage/` fixture, which stays.
    Dir.glob("project/**/coverage").each do |copied|
      relative = copied.delete_prefix("project/")
      tracked = system("git", "-C", source, "ls-files", "--error-unmatch", relative,
                       out: File::NULL, err: File::NULL)
      FileUtils.rm_rf(copied) unless tracked
    end
  end

  step 'I cd to "project"'
end
