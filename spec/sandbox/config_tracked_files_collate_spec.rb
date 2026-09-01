# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "tracked files across merges and collation", :sandbox do
  let(:tracking_config) do
    <<~RUBY
      require 'simplecov'
      SimpleCov.start do
        track_files "lib/**/*.rb"
      end
    RUBY
  end
  let(:data) { html_report_data }

  before do
    setup_project("faked_project")
    configure_simplecov(:test_unit, tracking_config)
  end

  def expect_tracked_file_percents(data, framework_specific:)
    expect(reported_file_percents(data)).to eq(
      "lib/faked_project.rb" => 100.00,
      "lib/faked_project/untested_class.rb" => 0.00,
      "lib/faked_project/some_class.rb" => 80.00,
      "lib/faked_project/framework_specific.rb" => framework_specific,
      "lib/faked_project/meta_magic.rb" => 100.00
    )
  end

  def stash_resultset(number)
    FileUtils.mv(File.join(sandbox_dir, "coverage/.resultset.json"),
      File.join(sandbox_dir, "coverage/resultset#{number}.json"))
    FileUtils.rm(File.join(sandbox_dir, "coverage/index.html"))
  end

  describe "two suites merging in one process" do
    before { configure_simplecov(:rspec, tracking_config) }

    context "when only the first suite has run" do
      let!(:result) { run_command_and_expect_success("bundle exec rake test") }

      it "generates a report" do
        expect_coverage_report_generated(result)
      end

      it "keeps the never-loaded tracked files" do
        expect_tracked_file_percents(data, framework_specific: 75.00)
      end
    end

    context "when the second suite has merged into it" do
      let!(:result) do
        run_command_and_expect_success("bundle exec rake test")
        run_command_and_expect_success(sorted_rspec_command)
      end

      it "generates a report" do
        expect_coverage_report_generated(result)
      end

      it "names both suites in the output" do
        expect(result.output).to include("Coverage report generated for RSpec, Unit Tests")
      end

      it "names both suites in the report" do
        expect(data.fetch("meta").fetch("command_name")).to eq("RSpec, Unit Tests")
      end

      it "totals the merged coverage" do
        expect(reported_total_percent(data)).to eq(79.16)
      end

      it "keeps the never-loaded tracked files" do
        expect_tracked_file_percents(data, framework_specific: 87.50)
      end
    end
  end

  describe "resultsets collated by a separate step" do
    let!(:result) do
      expect_coverage_report_generated(run_command_and_expect_success("bundle exec rake part1"))
      stash_resultset(1)
      expect_coverage_report_generated(run_command_and_expect_success("bundle exec rake part2"))
      stash_resultset(2)
      run_command_and_expect_success("bundle exec rake collate")
    end

    it "generates a report" do
      expect_coverage_report_generated(result)
    end

    it "totals the collated coverage" do
      expect(reported_total_percent(data)).to eq(77.08)
    end

    it "keeps the never-loaded tracked files" do
      expect_tracked_file_percents(data, framework_specific: 75.00)
    end
  end
end
