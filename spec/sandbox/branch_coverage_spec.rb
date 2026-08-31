# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "branch coverage", :sandbox do
  before { setup_project("faked_project") }

  def expect_line_and_branch_totals(data)
    expect(reported_total_percent(data)).to eq(88.09)
    expect(data.fetch("total").fetch("lines")).to include("covered" => 37, "total" => 42)
    expect(data.fetch("total").fetch("branches")).to include("covered" => 1, "total" => 2)
  end

  def expect_line_file_percents(data)
    expect(reported_file_percents(data)).to eq(
      "lib/faked_project.rb" => 100.00,
      "lib/faked_project/some_class.rb" => 80.00,
      "lib/faked_project/framework_specific.rb" => 75.00,
      "lib/faked_project/meta_magic.rb" => 100.00
    )
  end

  def expect_branch_file_percents(data)
    expect(reported_file_percents(data, criterion: "branches")).to eq(
      "lib/faked_project.rb" => 100.00,
      "lib/faked_project/some_class.rb" => 50.00,
      "lib/faked_project/framework_specific.rb" => 100.00,
      "lib/faked_project/meta_magic.rb" => 100.00
    )
  end

  def expect_some_class_branch_details(data)
    some_class = data.fetch("coverage").fetch("lib/faked_project/some_class.rb")
    expect(some_class).to include(
      "covered_lines" => 12, "total_lines" => 15,
      "covered_branches" => 1, "total_branches" => 2
    )
    expect(some_class.fetch("branches")).to include(
      a_hash_including("type" => "then", "coverage" => 1),
      a_hash_including("type" => "else", "coverage" => 0)
    )
  end

  it "reports branch coverage alongside line coverage" do
    configure_simplecov(:rspec, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        enable_coverage :branch
      end
    RUBY

    result = run_command_and_expect_success(sorted_rspec_command)
    expect_coverage_report_generated(result)
    expect(result.output).to include("Line coverage: 37 / 42 (88.09%)")
    expect(result.output).to include("Branch coverage: 1 / 2 (50.00%)")

    data = html_report_data
    expect(data.fetch("meta")).to include("line_coverage" => true, "branch_coverage" => true)
    expect_line_and_branch_totals(data)
    expect_line_file_percents(data)
    expect_branch_file_percents(data)
    expect_some_class_branch_details(data)
  end
end
