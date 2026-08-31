# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "criterion-only coverage reports", :sandbox do
  before { setup_project("faked_project") }

  def expect_branch_only_data(data)
    expect(data.fetch("meta")).to include(
      "line_coverage" => false, "branch_coverage" => true, "primary_coverage" => "branch"
    )
    expect(reported_total_percent(data, criterion: "branches")).to eq(50.00)
    expect(reported_file_percents(data, criterion: "branches")).to eq(
      "lib/faked_project.rb" => 100.00,
      "lib/faked_project/some_class.rb" => 50.00,
      "lib/faked_project/framework_specific.rb" => 100.00,
      "lib/faked_project/meta_magic.rb" => 100.00
    )
  end

  def expect_method_only_data(data)
    expect(data.fetch("meta")).to include(
      "line_coverage" => false, "method_coverage" => true, "primary_coverage" => "method"
    )
    expect(reported_total_percent(data, criterion: "methods")).to eq(75.00)
    expect(reported_file_percents(data, criterion: "methods")).to eq(
      "lib/faked_project.rb" => 100.00,
      "lib/faked_project/some_class.rb" => 75.00,
      "lib/faked_project/framework_specific.rb" => 33.33,
      "lib/faked_project/meta_magic.rb" => 100.00
    )
  end

  it "reports branch coverage only" do
    configure_simplecov(:rspec, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        disable_coverage :line
        enable_coverage :branch
        primary_coverage :branch
      end
    RUBY

    result = run_command_and_expect_success(sorted_rspec_command)
    expect_coverage_report_generated(result)
    expect(result.output).not_to include("Line coverage:")
    expect(result.output).to include("Branch coverage: 1 / 2 (50.00%)")

    data = html_report_data
    expect(data.fetch("total")).not_to have_key("lines")
    expect_branch_only_data(data)
    some_class = data.fetch("coverage").fetch("lib/faked_project/some_class.rb")
    expect(some_class).to include("covered_branches" => 1, "total_branches" => 2)
    expect(some_class).not_to have_key("lines_covered_percent")
    expect(some_class.fetch("branches")).to include(a_hash_including("type" => "else", "coverage" => 0))
  end

  it "reports method coverage only" do
    configure_simplecov(:rspec, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        disable_coverage :line
        enable_coverage :method
        primary_coverage :method
      end
    RUBY

    result = run_command_and_expect_success(sorted_rspec_command)
    expect_coverage_report_generated(result)
    expect(result.output).not_to include("Line coverage:")
    expect(result.output).to include("Method coverage: 9 / 12 (75.00%)")

    data = html_report_data
    expect(data.fetch("total")).not_to have_key("lines")
    expect_method_only_data(data)
    expect(data.fetch("coverage").fetch("lib/faked_project/some_class.rb"))
      .to include("covered_methods" => 3, "total_methods" => 4)
  end
end
