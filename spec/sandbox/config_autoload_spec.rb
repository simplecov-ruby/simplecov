# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "config autoload via .simplecov", :sandbox do
  before do
    setup_project("faked_project")
    write_file(".simplecov", <<~RUBY)
      SimpleCov.start do
        add_filter 'test.rb'
        add_filter 'spec.rb'
      end
    RUBY
    configure_simplecov(:test_unit, "require 'simplecov'")
    configure_simplecov(:rspec, "require 'simplecov'")
  end

  def html_file_percents(data)
    data.fetch("coverage").transform_values { |file| displayed_percent(file.fetch("lines_covered_percent")) }
  end

  it "applies the shared .simplecov config to both suites and merges their results" do
    run_command_and_expect_success("bundle exec rake test")
    result = run_command_and_expect_success(sorted_rspec_command)
    expect_coverage_report_generated(result)
    expect(result.output).to include("Coverage report generated for RSpec, Unit Tests")

    data = html_report_data
    expect(data.dig("meta", "command_name")).to eq("RSpec, Unit Tests")
    expect(displayed_percent(data.dig("total", "lines", "percent"))).to eq(90.47)
    expect(html_file_percents(data)).to eq(
      "lib/faked_project.rb" => 100.00,
      "lib/faked_project/some_class.rb" => 80.00,
      "lib/faked_project/framework_specific.rb" => 87.50,
      "lib/faked_project/meta_magic.rb" => 100.00
    )
  end
end
