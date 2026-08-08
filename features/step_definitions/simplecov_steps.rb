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

# Ages what's already stored instead of really sleeping: the merge only
# compares the recorded timestamps against merge_timeout, so backdating
# the data is equivalent and keeps real wall-clock waits out of the
# suite.
When /^the stored resultset is (\d+) seconds older$/ do |seconds|
  in_current_directory do
    path = "coverage/.resultset.json"
    data = JSON.parse(File.read(path))
    data.each_value { |entry| entry["timestamp"] -= seconds.to_i }
    File.write(path, JSON.dump(data))
  end
end

Then "the overlay should be open" do
  expect(page).to have_css("#source-dialog[open]")
end

When "I install dependencies" do
  # When the sandbox's shipped lockfile is already satisfied by the
  # installed gems, `bundle check` answers in a fraction of a full
  # resolve — and some features install the same project's dependencies
  # once per scenario. Anything else (missing gems, or a lockfile
  # written by a conflicting bundler on another Ruby version) falls back
  # to the original path: drop the lock and resolve fresh.
  run_command_and_stop("bundle check", fail_on_error: false)
  next if last_command_started.exit_status.zero?

  # Parallel workers resolve different sandboxes but install into the
  # one shared gem home, and rubygems' native-extension builds are not
  # concurrency-safe: two simultaneous installs of the same gem compile
  # in the same ext directory and the loser dies mid-make with a
  # Gem::Ext::BuildError ("can't create bigdecimal.o"). Serialize the
  # install path across workers — the warm `bundle check` above stays
  # parallel — and re-check once the lock is held, because the worker
  # that held it first usually installed exactly what this one misses.
  with_cross_worker_install_lock do
    run_command_and_stop("bundle check", fail_on_error: false)
    next if last_command_started.exit_status.zero?

    in_current_directory { FileUtils.rm_f("Gemfile.lock") }
    # bundle may take its time
    steps %(
      When I successfully run `bundle` for up to 120 seconds
    )
  end
end

def with_cross_worker_install_lock
  path = File.expand_path("../../tmp/cucumber-bundle-install.lock", __dir__)
  FileUtils.mkdir_p(File.dirname(path))
  File.open(path, File::CREAT | File::RDWR) do |lock|
    lock.flock(File::LOCK_EX)
    yield
  end
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
