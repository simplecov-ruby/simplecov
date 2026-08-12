# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# Rails loads Minitest's autorun machinery before test/test_helper.rb, and
# ActiveSupport's process parallelization forks after SimpleCov starts. This
# fixture covers both Rails-specific integration paths with the stock Minitest
# stack that ships with Rails (not the third-party minitest-rails gem).
RSpec.describe "Rails Minitest integration", :sandbox do
  before do
    setup_project("rails/minitest_rails")
    install_dependencies
  end

  it "merges coverage from a parallel bin/rails test run" do
    result = run_command_and_expect_success("bin/rails test", timeout: 120)
    expect_coverage_report_generated(result)

    data = html_report_data
    expect(reported_total_percent(data)).to eq(100.00)
    expect(reported_file_percents(data)).to eq(
      "app/models/order.rb" => 100.00,
      "app/models/receipt.rb" => 100.00
    )

    worker_pids = Dir.glob(File.join(sandbox_dir, "tmp/worker_pids/*")).map { |path| File.read(path) }
    expect(worker_pids.uniq.length).to eq(2)

    subprocess_results = resultset_json.keys.grep(/ \(subprocess: \d+\)\z/)
    expect(subprocess_results.length).to eq(2)
  end
end
