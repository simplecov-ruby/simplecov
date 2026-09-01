# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "test/unit integration", :sandbox do
  before { setup_project("faked_project") }

  let(:data) { html_report_data }
  let(:expected_file_percents) do
    {
      "lib/faked_project.rb" => 100.00,
      "lib/faked_project/some_class.rb" => 80.00,
      "lib/faked_project/framework_specific.rb" => 75.00,
      "lib/faked_project/meta_magic.rb" => 100.00
    }
  end
  let!(:result) do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start
    RUBY
    run_command_and_expect_success("bundle exec rake test")
  end

  it "generates a report from the basic two-line setup" do
    expect_coverage_report_generated(result)
  end

  it "names the suite in the output" do
    expect(result.output).to include("Coverage report generated for Unit Tests")
  end

  it "names the suite in the report" do
    expect(data.dig("meta", "command_name")).to eq("Unit Tests")
  end

  it "totals the coverage" do
    expect(reported_total_percent(data)).to eq(88.09)
  end

  it "reports each file's percentage" do
    expect(reported_file_percents(data)).to eq(expected_file_percents)
  end
end
