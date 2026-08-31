# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "many-file reports", :sandbox do
  before { setup_project("pagination") }

  it "reports every one of the twelve files with its source" do
    result = run_command_and_expect_success("bundle exec rspec")
    expect_coverage_report_generated(result)

    data = html_report_data
    expect(reported_total_percent(data)).to eq(100.00)

    expected_files = ("a".."l").map { |name| "lib/#{name}.rb" }
    expect(data.fetch("coverage").keys).to match_array(expected_files)
    expect(reported_file_percents(data)).to eq(expected_files.to_h { |file| [file, 100.00] })

    expect(data.fetch("coverage").fetch("lib/a.rb").fetch("source").join).to include("nothing to see here")
    expect(data.fetch("coverage").fetch("lib/l.rb").fetch("source").join).to include("nothing to see here")
  end
end
