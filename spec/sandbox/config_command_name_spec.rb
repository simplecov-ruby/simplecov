# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "custom command names for test suites", :sandbox do
  before { setup_project("faked_project") }

  it "reports under the custom names and merges suites under both names" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        command_name "I'm in UR Unitz"
      end
    RUBY
    configure_simplecov(:rspec, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        command_name "Dreck macht Speck"
      end
    RUBY

    result = run_command_and_expect_success("bundle exec rake test")
    expect_coverage_report_generated(result)
    expect(result.output).to include("Coverage report generated for I'm in UR Unitz")
    expect(html_report_data.dig("meta", "command_name")).to eq("I'm in UR Unitz")

    result = run_command_and_expect_success(sorted_rspec_command)
    expect_coverage_report_generated(result)
    expect(result.output).to include("Coverage report generated for Dreck macht Speck, I'm in UR Unitz")
    expect(html_report_data.dig("meta", "command_name")).to eq("Dreck macht Speck, I'm in UR Unitz")
  end

  it "auto-detects RSpec even when a spec/features directory exists" do
    configure_simplecov(:rspec, <<~RUBY)
      require 'simplecov'
      SimpleCov.start
    RUBY
    write_file("spec/features/foobar_spec.rb", "")

    result = run_command_and_expect_success(sorted_rspec_command)
    expect_coverage_report_generated(result)
    expect(result.output).to include("Coverage report generated for RSpec")
    expect(html_report_data.dig("meta", "command_name")).to eq("RSpec")
  end
end
