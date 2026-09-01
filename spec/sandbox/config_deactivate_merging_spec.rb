# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "deactivated merging", :sandbox do
  before do
    setup_project("faked_project")
    config = <<~RUBY
      require 'simplecov'
      SimpleCov.start do
        use_merging false
      end
    RUBY
    configure_simplecov(:test_unit, config)
    configure_simplecov(:rspec, config)
  end

  def expect_unmerged_report(result, suite)
    expect(result.output).to include("Coverage report generated for #{suite}")
    expect(file_exist?("coverage/index.html")).to be(true)
    expect(file_exist?("coverage/.resultset.json")).to be(false)
    expect(html_report_data.dig("meta", "command_name")).to eq(suite)
  end

  it "overwrites the report with the latest suite instead of merging" do
    expect_unmerged_report(run_command_and_expect_success("bundle exec rake test"), "Unit Tests")
    expect_unmerged_report(run_command_and_expect_success("bundle exec rspec spec"), "RSpec")
  end
end
