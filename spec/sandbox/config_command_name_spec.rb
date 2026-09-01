# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "custom command names for test suites", :sandbox do
  before { setup_project("faked_project") }

  describe "naming each suite" do
    before do
      configure_simplecov(:test_unit, <<~RUBY)
        require 'simplecov'
        SimpleCov.start do
          command_name "I'm in UR Unitz"
        end
      RUBY
      configure_simplecov(:rspec, <<~RUBY)
        require 'simplecov'
        SimpleCov.start do
          command_name "Dreck macht Speck"
        end
      RUBY
    end

    context "when only the unit suite has run" do
      let!(:result) { run_command_and_expect_success("bundle exec rake test") }

      it "generates a report" do
        expect_coverage_report_generated(result)
      end

      it "names the unit suite in the output" do
        expect(result.output).to include("Coverage report generated for I'm in UR Unitz")
      end

      it "names the unit suite in the report" do
        expect(html_report_data.dig("meta", "command_name")).to eq("I'm in UR Unitz")
      end
    end

    context "when the rspec suite has run on top of it" do
      before { run_command_and_expect_success("bundle exec rake test") }

      let!(:result) { run_command_and_expect_success(sorted_rspec_command) }

      it "generates a report" do
        expect_coverage_report_generated(result)
      end

      it "names both suites in the output" do
        expect(result.output).to include("Coverage report generated for Dreck macht Speck, I'm in UR Unitz")
      end

      it "names both suites in the report" do
        expect(html_report_data.dig("meta", "command_name")).to eq("Dreck macht Speck, I'm in UR Unitz")
      end
    end
  end

  describe "auto-detecting RSpec when a spec/features directory exists" do
    before do
      configure_simplecov(:rspec, <<~RUBY)
        require 'simplecov'
        SimpleCov.start
      RUBY
      write_file("spec/features/foobar_spec.rb", "")
    end

    let!(:result) { run_command_and_expect_success(sorted_rspec_command) }

    it "generates a report" do
      expect_coverage_report_generated(result)
    end

    it "names RSpec in the output" do
      expect(result.output).to include("Coverage report generated for RSpec")
    end

    it "names RSpec in the report" do
      expect(html_report_data.dig("meta", "command_name")).to eq("RSpec")
    end
  end
end
