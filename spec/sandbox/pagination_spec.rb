# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "many-file reports", :sandbox do
  before { setup_project("pagination") }

  let!(:result) { run_command_and_expect_success("bundle exec rspec") }
  let(:data) { html_report_data }
  let(:expected_files) { ("a".."l").map { |name| "lib/#{name}.rb" } }

  it "generates a report" do
    expect_coverage_report_generated(result)
  end

  it "totals the coverage" do
    expect(reported_total_percent(data)).to eq(100.00)
  end

  it "reports every one of the twelve files" do
    expect(data.fetch("coverage").keys).to match_array(expected_files)
  end

  it "reports each file's percentage" do
    expect(reported_file_percents(data)).to eq(expected_files.to_h { |file| [file, 100.00] })
  end

  it "keeps the first file's source" do
    expect(data.fetch("coverage").fetch("lib/a.rb").fetch("source").join).to include("nothing to see here")
  end

  it "keeps the last file's source" do
    expect(data.fetch("coverage").fetch("lib/l.rb").fetch("source").join).to include("nothing to see here")
  end
end
