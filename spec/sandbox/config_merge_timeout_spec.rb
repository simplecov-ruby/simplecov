# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "merge timeout", :sandbox do
  before do
    setup_project("faked_project")
    config = <<~RUBY
      require 'simplecov'
      SimpleCov.start do
        merge_timeout 5
      end
    RUBY
    configure_simplecov(:test_unit, config)
    configure_simplecov(:rspec, config)
  end

  def age_stored_resultset(seconds)
    data = resultset_json
    data.each_value { |entry| entry["timestamp"] -= seconds }
    write_file("coverage/.resultset.json", JSON.dump(data))
  end

  context "when the first suite has run" do
    let!(:result) { run_command_and_expect_success("bundle exec rake test") }

    it "generates a report" do
      expect_coverage_report_generated(result)
    end

    it "names the first suite in the report" do
      expect(html_report_data.dig("meta", "command_name")).to eq("Unit Tests")
    end
  end

  context "when the stored resultset has aged past the timeout" do
    let!(:result) do
      run_command_and_expect_success("bundle exec rake test")
      age_stored_resultset(6)
      run_command_and_expect_success("bundle exec rspec spec")
    end

    it "generates a report" do
      expect_coverage_report_generated(result)
    end

    it "names only the second suite in the output" do
      expect(result.output).to include("Coverage report generated for RSpec")
    end

    it "names only the second suite in the report" do
      expect(html_report_data.dig("meta", "command_name")).to eq("RSpec")
    end
  end
end
