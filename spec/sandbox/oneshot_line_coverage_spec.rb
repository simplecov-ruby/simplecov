# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "oneshot line coverage", :sandbox do
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
    configure_simplecov(:rspec, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        enable_coverage :oneshot_line
        primary_coverage :oneshot_line
      end
    RUBY
    run_command_and_expect_success(sorted_rspec_command)
  end

  it "generates a report" do
    expect_coverage_report_generated(result)
  end

  it "records the criterion in the report meta" do
    expect(data.fetch("meta")).to include("line_coverage" => true, "primary_coverage" => "oneshot_line")
  end

  it "totals the same as many-shot line coverage" do
    expect(reported_total_percent(data)).to eq(88.09)
  end

  it "counts the same lines as many-shot line coverage" do
    expect(data.fetch("total").fetch("lines")).to include("covered" => 37, "total" => 42)
  end

  it "reports the same per-file percentages as many-shot line coverage" do
    expect(reported_file_percents(data)).to eq(expected_file_percents)
  end

  it "counts a partially covered file's lines" do
    expect(data.fetch("coverage").fetch("lib/faked_project/some_class.rb"))
      .to include("covered_lines" => 12, "total_lines" => 15)
  end
end
