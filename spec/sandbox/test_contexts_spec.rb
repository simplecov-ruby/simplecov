# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# `test_contexts :per_test` end to end: the suite records which test
# covered each line, the recording lands in `.resultset.json`, flows
# into coverage.json and the HTML payload, and `simplecov who-covers`
# answers from it — including the "covered by setup only" case (a `def`
# line executes at load time, not in any test).
RSpec.describe "per-test contexts", :sandbox do
  before { setup_project("faked_project") }

  def stored_contexts
    entries = resultset_json.values
    expect(entries.size).to eq 1
    entries.first.fetch("test_contexts")
  end

  def run_recorded_rspec_suite
    configure_simplecov(:rspec, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        test_contexts :per_test
      end
      #{SandboxProject::JSON_ALONGSIDE_HTML}
    RUBY

    run_command_and_expect_success(sorted_rspec_command)
  end

  it "records rspec examples in the resultset and the report payloads" do
    expect_coverage_report_generated(run_recorded_rspec_suite)

    contexts = stored_contexts
    expect(contexts.fetch("version")).to eq 1
    expect(contexts.fetch("tests").map(&:last)).to include("SomeClass should be reversible")
    expect(contexts.fetch("files").keys).to include(end_with("lib/faked_project/some_class.rb"))

    # The rerun ids + names flow into coverage.json and the HTML payload.
    json = coverage_json
    ids = json.fetch("meta").fetch("test_contexts").fetch("tests").map { |test| test.fetch("id") }
    expect(ids).to include(include("some_class_spec.rb["))
    expect(json.dig("coverage", "lib/faked_project/some_class.rb", "test_contexts")).not_to be_empty
    expect(html_report_data.dig("meta", "test_contexts", "tests")).to eq(
      json.dig("meta", "test_contexts", "tests")
    )
  end

  it "answers who-covers from the recorded resultset" do
    run_recorded_rspec_suite

    # `label.reverse` runs inside examples; `def initialize` ran at load.
    # `--input` is explicit because the sandbox sits inside the simplecov
    # repository, whose own `.simplecov` would otherwise win the CLI's
    # upward dotfile walk.
    who_covers = "bundle exec simplecov who-covers --input coverage/.resultset.json"
    answer = run_command_and_expect_success("#{who_covers} lib/faked_project/some_class.rb:12")
    expect(answer.output).to match(/line 12: covered by \d+ tests?:/)
    expect(answer.output).to include("SomeClass should be reversible")

    setup_only = run_command_and_expect_success("#{who_covers} lib/faked_project/some_class.rb:7")
    expect(setup_only.output).to include("line 7: covered, but by no recorded test")
  end

  it "records minitest tests through the plugin" do
    self.bundle_with = "minitest"
    install_dependencies
    configure_simplecov(:minitest, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        test_contexts :per_test
        add_filter "test_helper.rb"
      end
    RUBY

    run_command_and_expect_success("bundle exec rake minitest")

    contexts = stored_contexts
    ids = contexts.fetch("tests").map(&:first)
    expect(ids).to include("SomeTest#test_reverse")
    expect(contexts.fetch("files").keys).to include(end_with("lib/faked_project/some_class.rb"))
  end

  it "stores no recording when the mode is off" do
    configure_simplecov(:rspec, <<~RUBY)
      require 'simplecov'
      SimpleCov.start
      #{SandboxProject::JSON_ALONGSIDE_HTML}
    RUBY

    run_command_and_expect_success(sorted_rspec_command)

    expect(resultset_json.values.first).not_to have_key("test_contexts")
    expect(coverage_json.fetch("meta")).not_to have_key("test_contexts")
  end
end
