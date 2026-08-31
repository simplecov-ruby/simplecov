# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "running with warnings enabled", :sandbox do
  before do
    skip "JRuby emits its own warnings" if RUBY_ENGINE == "jruby"
    setup_project("faked_project")
  end

  it "generates a report without any warnings in the output" do
    configure_simplecov(:rspec, <<~RUBY)
      require 'simplecov'
      SimpleCov.start
    RUBY

    result = run_command_and_expect_success("bundle exec rspec --warnings spec")
    expect_coverage_report_generated(result)
    expect(result.output).not_to include("warning")
  end
end
