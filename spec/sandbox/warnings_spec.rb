# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "running with warnings enabled", :sandbox do
  let(:result) { run_command_and_expect_success("bundle exec rspec --warnings spec") }

  before do
    skip "JRuby emits its own warnings" if RUBY_ENGINE == "jruby"
    setup_project("faked_project")
    configure_simplecov(:rspec, <<~RUBY)
      require 'simplecov'
      SimpleCov.start
    RUBY
  end

  it "generates a report" do
    expect_coverage_report_generated(result)
  end

  it "prints no warning" do
    expect(result.output).not_to include("warning")
  end
end
