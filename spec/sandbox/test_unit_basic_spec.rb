# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "test/unit integration", :sandbox do
  before { setup_project("faked_project") }

  it "generates a coverage report from the basic two-line setup" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start
    RUBY

    result = run_command_and_expect_success("bundle exec rake test")
    expect_coverage_report_generated(result)
    expect(result.output).to include("Coverage report generated for Unit Tests")

    data = html_report_data
    expect(data.dig("meta", "command_name")).to eq("Unit Tests")
    expect(reported_total_percent(data)).to eq(88.09)
    expect(reported_file_percents(data)).to eq(
      "lib/faked_project.rb" => 100.00,
      "lib/faked_project/some_class.rb" => 80.00,
      "lib/faked_project/framework_specific.rb" => 75.00,
      "lib/faked_project/meta_magic.rb" => 100.00
    )
  end
end
