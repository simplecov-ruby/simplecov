# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "branch coverage", :sandbox do
  before do
    setup_project("faked_project")
    configure_simplecov(:rspec, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        enable_coverage :branch
      end
    RUBY
  end

  let!(:result) { run_command_and_expect_success(sorted_rspec_command) }
  let(:data) { html_report_data }
  let(:some_class) { data.fetch("coverage").fetch("lib/faked_project/some_class.rb") }
  let(:expected_line_percents) do
    {
      "lib/faked_project.rb" => 100.00,
      "lib/faked_project/some_class.rb" => 80.00,
      "lib/faked_project/framework_specific.rb" => 75.00,
      "lib/faked_project/meta_magic.rb" => 100.00
    }
  end
  let(:expected_branch_percents) do
    {
      "lib/faked_project.rb" => 100.00,
      "lib/faked_project/some_class.rb" => 50.00,
      "lib/faked_project/framework_specific.rb" => 100.00,
      "lib/faked_project/meta_magic.rb" => 100.00
    }
  end

  it "generates a report" do
    expect_coverage_report_generated(result)
  end

  it "prints the line coverage summary" do
    expect(result.output).to include("Line coverage: 37 / 42 (88.09%)")
  end

  it "prints the branch coverage summary" do
    expect(result.output).to include("Branch coverage: 1 / 2 (50.00%)")
  end

  it "records both criteria in the report meta" do
    expect(data.fetch("meta")).to include("line_coverage" => true, "branch_coverage" => true)
  end

  it "reports the overall line percentage" do
    expect(reported_total_percent(data)).to eq(88.09)
  end

  it "totals the lines it measured" do
    expect(data.fetch("total").fetch("lines")).to include("covered" => 37, "total" => 42)
  end

  it "totals the branches it measured" do
    expect(data.fetch("total").fetch("branches")).to include("covered" => 1, "total" => 2)
  end

  it "reports each file's line percentage" do
    expect(reported_file_percents(data)).to eq(expected_line_percents)
  end

  it "reports each file's branch percentage" do
    expect(reported_file_percents(data, criterion: "branches")).to eq(expected_branch_percents)
  end

  it "counts a partially covered file's lines and branches" do
    expect(some_class).to include(
      "covered_lines" => 12, "total_lines" => 15,
      "covered_branches" => 1, "total_branches" => 2
    )
  end

  it "records which of a partially covered file's branches ran" do
    expect(some_class.fetch("branches")).to include(
      a_hash_including("type" => "then", "coverage" => 1),
      a_hash_including("type" => "else", "coverage" => 0)
    )
  end
end
