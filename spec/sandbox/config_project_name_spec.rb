# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "project name in the report", :sandbox do
  before { setup_project("faked_project") }

  describe "the default name" do
    let!(:result) do
      configure_simplecov(:test_unit, <<~RUBY)
        require 'simplecov'
        SimpleCov.start
      RUBY
      run_command_and_expect_success("bundle exec rake test")
    end

    it "generates a report" do
      expect_coverage_report_generated(result)
    end

    it "is guessed from the project root directory" do
      expect(html_report_data.dig("meta", "project_name")).to eq("Project")
    end
  end

  describe "a configured name" do
    let!(:result) do
      configure_simplecov(:test_unit, <<~RUBY)
        require 'simplecov'
        SimpleCov.start { project_name "Superfancy 2.0" }
      RUBY
      run_command_and_expect_success("bundle exec rake test")
    end

    it "generates a report" do
      expect_coverage_report_generated(result)
    end

    it "is used in the report" do
      expect(html_report_data.dig("meta", "project_name")).to eq("Superfancy 2.0")
    end
  end
end
