# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "coverage for subprocesses", :sandbox do
  before do
    skip "the fixture forks subprocesses" unless Process.respond_to?(:fork)
    setup_project("subprocesses")
  end

  def expect_fully_covered_single_file(data)
    expect(reported_total_percent(data)).to eq(100.00)
    expect(data.fetch("coverage").size).to eq(1)
  end

  describe "a plain fork" do
    let!(:result) { run_command_and_expect_success("bundle exec rspec spec/simple_spec.rb") }

    it "generates a report" do
      expect_coverage_report_generated(result)
    end

    it "sees the line only the subprocess runs" do
      expect_fully_covered_single_file(html_report_data)
    end
  end

  describe "an at_fork proc" do
    let(:merged_name) { "child process name, parent process name" }
    let!(:result) do
      write_file(".simplecov", <<~RUBY)
        SimpleCov.merge_subprocesses true
        SimpleCov.command_name "parent process name"
        SimpleCov.at_fork do |_pid|
          SimpleCov.command_name "child process name"
          SimpleCov.start
        end
      RUBY
      run_command_and_expect_success("bundle exec rspec spec/simple_spec.rb")
    end

    it "generates a report" do
      expect_coverage_report_generated(result)
    end

    it "names both processes in the output" do
      expect(result.output).to include("Coverage report generated for #{merged_name}")
    end

    it "names both processes in the report" do
      expect(html_report_data.dig("meta", "command_name")).to eq(merged_name)
    end

    it "runs in the child and merges its results" do
      expect_fully_covered_single_file(html_report_data)
    end
  end

  describe "a parent that defers its report externally" do
    let(:merged_name) { "parent process name, parent process name (subprocess: 1)" }
    let!(:result) do
      write_file(".simplecov", <<~RUBY)
        SimpleCov.merge_subprocesses true
        SimpleCov.command_name "parent process name"
        SimpleCov.add_filter /command/
        SimpleCov.add_filter /spawn/
      RUBY
      write_file("external_exit.rb", <<~RUBY)
        require "simplecov"
        SimpleCov.start
        SimpleCov.external_at_exit = true
        require_relative "lib/subprocesses"
        Subprocesses.new.run
        SimpleCov.at_exit_behavior
      RUBY
      run_command_and_expect_success("bundle exec ruby external_exit.rb")
    end

    it "generates a report" do
      expect_coverage_report_generated(result)
    end

    it "names both processes in the output" do
      expect(result.output).to include("Coverage report generated for #{merged_name}")
    end

    it "names both processes in the report" do
      expect(html_report_data.dig("meta", "command_name")).to eq(merged_name)
    end

    it "merges the forked children in" do
      expect_fully_covered_single_file(html_report_data)
    end
  end

  describe "a spawned command" do
    let!(:result) { run_command_and_expect_success("bundle exec rspec spec/spawn_spec.rb") }

    it "generates a report" do
      expect_coverage_report_generated(result)
    end

    it "is covered through .simplecov_spawn" do
      expect_fully_covered_single_file(html_report_data)
    end
  end
end
