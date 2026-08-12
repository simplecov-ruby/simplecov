# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# Oneshot line coverage records only whether a line was ever hit, not how
# often; the resulting report carries the same percentages as regular
# line coverage. The viewer normalizes the "oneshot_line" primary
# coverage name back to the line criterion (covered by the bun suite,
# html_frontend/test/coverage.test.ts).
RSpec.describe "oneshot line coverage", :sandbox do
  before { setup_project("faked_project") }

  def expect_regular_line_coverage_report(data)
    expect(reported_total_percent(data)).to eq(88.09)
    expect(data.fetch("total").fetch("lines")).to include("covered" => 37, "total" => 42)
    expect(reported_file_percents(data)).to eq(
      "lib/faked_project.rb" => 100.00,
      "lib/faked_project/some_class.rb" => 80.00,
      "lib/faked_project/framework_specific.rb" => 75.00,
      "lib/faked_project/meta_magic.rb" => 100.00
    )
  end

  it "produces the same line coverage report as many-shot line coverage" do
    configure_simplecov(:rspec, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        enable_coverage :oneshot_line
        primary_coverage :oneshot_line
      end
    RUBY

    result = run_command_and_expect_success(sorted_rspec_command)
    expect_coverage_report_generated(result)

    data = html_report_data
    expect(data.fetch("meta")).to include("line_coverage" => true, "primary_coverage" => "oneshot_line")
    expect_regular_line_coverage_report(data)
    expect(data.fetch("coverage").fetch("lib/faked_project/some_class.rb"))
      .to include("covered_lines" => 12, "total_lines" => 15)
  end
end
