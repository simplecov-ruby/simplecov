# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "Rails Minitest integration", :sandbox do
  before do
    setup_project("rails/minitest_rails")
    install_dependencies
  end

  let!(:result) { run_command_and_expect_success("bin/rails test", timeout: 120) }
  let(:data) { html_report_data }
  let(:worker_pids) { Dir.glob(File.join(sandbox_dir, "tmp/worker_pids/*")).map { |path| File.read(path) } }

  it "generates a report" do
    expect_coverage_report_generated(result)
  end

  it "totals the coverage" do
    expect(reported_total_percent(data)).to eq(100.00)
  end

  it "reports each file's percentage" do
    expect(reported_file_percents(data)).to eq(
      "app/models/order.rb" => 100.00,
      "app/models/receipt.rb" => 100.00
    )
  end

  it "runs the tests across two workers" do
    expect(worker_pids.uniq.length).to eq(2)
  end

  it "merges a resultset from each of them" do
    expect(resultset_json.keys.grep(/ \(subprocess: \d+\)\z/).length).to eq(2)
  end
end
