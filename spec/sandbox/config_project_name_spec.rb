# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "project name in the report", :sandbox do
  before { setup_project("faked_project") }

  it "guesses the name from the project root directory" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start
    RUBY

    result = run_command_and_expect_success("bundle exec rake test")
    expect_coverage_report_generated(result)
    expect(html_report_data.dig("meta", "project_name")).to eq("Project")
  end

  it "uses a custom name when configured" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start { project_name "Superfancy 2.0" }
    RUBY

    result = run_command_and_expect_success("bundle exec rake test")
    expect_coverage_report_generated(result)
    expect(html_report_data.dig("meta", "project_name")).to eq("Superfancy 2.0")
  end
end
