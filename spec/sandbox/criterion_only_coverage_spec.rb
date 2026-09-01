# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "criterion-only coverage reports", :sandbox do
  before { setup_project("faked_project") }

  let(:data) { html_report_data }
  let(:some_class) { data.fetch("coverage").fetch("lib/faked_project/some_class.rb") }

  describe "branch coverage only" do
    let(:expected_file_percents) do
      {
        "lib/faked_project.rb" => 100.00,
        "lib/faked_project/some_class.rb" => 50.00,
        "lib/faked_project/framework_specific.rb" => 100.00,
        "lib/faked_project/meta_magic.rb" => 100.00
      }
    end
    let!(:result) do
      configure_simplecov(:rspec, <<~RUBY)
        require 'simplecov'
        SimpleCov.start do
          disable_coverage :line
          enable_coverage :branch
          primary_coverage :branch
        end
      RUBY
      run_command_and_expect_success(sorted_rspec_command)
    end

    it "generates a report" do
      expect_coverage_report_generated(result)
    end

    it "prints no line coverage summary" do
      expect(result.output).not_to include("Line coverage:")
    end

    it "prints the branch coverage summary" do
      expect(result.output).to include("Branch coverage: 1 / 2 (50.00%)")
    end

    it "records only branches in the report meta" do
      expect(data.fetch("meta")).to include(
        "line_coverage" => false, "branch_coverage" => true, "primary_coverage" => "branch"
      )
    end

    it "leaves lines out of the total" do
      expect(data.fetch("total")).not_to have_key("lines")
    end

    it "reports the overall branch percentage" do
      expect(reported_total_percent(data, criterion: "branches")).to eq(50.00)
    end

    it "reports each file's branch percentage" do
      expect(reported_file_percents(data, criterion: "branches")).to eq(expected_file_percents)
    end

    it "counts a partially covered file's branches" do
      expect(some_class).to include("covered_branches" => 1, "total_branches" => 2)
    end

    it "leaves lines out of a file's figures" do
      expect(some_class).not_to have_key("lines_covered_percent")
    end

    it "records which of a file's branches ran" do
      expect(some_class.fetch("branches")).to include(a_hash_including("type" => "else", "coverage" => 0))
    end
  end

  describe "method coverage only" do
    let(:expected_file_percents) do
      {
        "lib/faked_project.rb" => 100.00,
        "lib/faked_project/some_class.rb" => 75.00,
        "lib/faked_project/framework_specific.rb" => 33.33,
        "lib/faked_project/meta_magic.rb" => 100.00
      }
    end
    let!(:result) do
      configure_simplecov(:rspec, <<~RUBY)
        require 'simplecov'
        SimpleCov.start do
          disable_coverage :line
          enable_coverage :method
          primary_coverage :method
        end
      RUBY
      run_command_and_expect_success(sorted_rspec_command)
    end

    it "generates a report" do
      expect_coverage_report_generated(result)
    end

    it "prints no line coverage summary" do
      expect(result.output).not_to include("Line coverage:")
    end

    it "prints the method coverage summary" do
      expect(result.output).to include("Method coverage: 9 / 12 (75.00%)")
    end

    it "records only methods in the report meta" do
      expect(data.fetch("meta")).to include(
        "line_coverage" => false, "method_coverage" => true, "primary_coverage" => "method"
      )
    end

    it "leaves lines out of the total" do
      expect(data.fetch("total")).not_to have_key("lines")
    end

    it "reports the overall method percentage" do
      expect(reported_total_percent(data, criterion: "methods")).to eq(75.00)
    end

    it "reports each file's method percentage" do
      expect(reported_file_percents(data, criterion: "methods")).to eq(expected_file_percents)
    end

    it "counts a partially covered file's methods" do
      expect(some_class).to include("covered_methods" => 3, "total_methods" => 4)
    end
  end
end
