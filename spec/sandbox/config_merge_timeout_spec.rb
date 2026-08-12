# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# The maximum age at which stored results still merge is customizable
# via SimpleCov.merge_timeout. A timeout shorter than the gap between
# two suite runs makes the first suite's results expire, so the second
# report is based on that suite alone.
RSpec.describe "merge timeout", :sandbox do
  before { setup_project("faked_project") }

  # Ages what's already stored instead of really sleeping: the merge only
  # compares the recorded timestamps against merge_timeout, so backdating
  # the data is equivalent and keeps real wall-clock waits out of the suite.
  def age_stored_resultset(seconds)
    data = resultset_json
    data.each_value { |entry| entry["timestamp"] -= seconds }
    write_file("coverage/.resultset.json", JSON.dump(data))
  end

  it "expires resultsets older than the merge timeout" do
    config = <<~RUBY
      require 'simplecov'
      SimpleCov.start do
        merge_timeout 5
      end
    RUBY
    configure_simplecov(:test_unit, config)
    configure_simplecov(:rspec, config)

    result = run_command_and_expect_success("bundle exec rake test")
    expect_coverage_report_generated(result)
    expect(html_report_data.dig("meta", "command_name")).to eq("Unit Tests")

    age_stored_resultset(6)

    result = run_command_and_expect_success("bundle exec rspec spec")
    expect_coverage_report_generated(result)
    expect(result.output).to include("Coverage report generated for RSpec")
    expect(html_report_data.dig("meta", "command_name")).to eq("RSpec")
  end
end
