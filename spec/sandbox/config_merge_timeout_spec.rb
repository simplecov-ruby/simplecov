# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "merge timeout", :sandbox do
  before { setup_project("faked_project") }

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
