# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# Test suites like RSpec and Test/Unit should be merged automatically
# when both have been run recently: the second suite's report features
# the joined results of every suite that is using SimpleCov.
RSpec.describe "merging test_unit and rspec results", :sandbox do
  before { setup_project("faked_project") }

  def configure_both_suites
    config = <<~RUBY
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        add_filter 'spec.rb'
      end
    RUBY
    configure_simplecov(:test_unit, config)
    configure_simplecov(:rspec, config)
  end

  def expect_report_based_upon(result, suites)
    expect_coverage_report_generated(result)
    expect(result.output).to include("Coverage report generated for #{suites}")
    expect(html_report_data.dig("meta", "command_name")).to eq(suites)
  end

  def expect_merged_percents
    data = html_report_data
    expect(reported_total_percent(data)).to eq(90.47)
    expect(reported_file_percents(data)).to eq(
      "lib/faked_project.rb" => 100.00,
      "lib/faked_project/some_class.rb" => 80.00,
      "lib/faked_project/framework_specific.rb" => 87.50,
      "lib/faked_project/meta_magic.rb" => 100.00
    )
  end

  it "merges both suites' results into the second report" do
    configure_both_suites

    expect_report_based_upon(run_command_and_expect_success("bundle exec rake test"), "Unit Tests")
    expect_report_based_upon(run_command_and_expect_success(sorted_rspec_command), "RSpec, Unit Tests")
    expect_merged_percents
  end
end
