# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "tracked files across merges and collation", :sandbox do
  before { setup_project("faked_project") }

  let(:tracking_config) do
    <<~RUBY
      require 'simplecov'
      SimpleCov.start do
        track_files "lib/**/*.rb"
      end
    RUBY
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

  it "keeps never-loaded tracked files when two suites merge in one process" do
    configure_simplecov(:test_unit, tracking_config)
    configure_simplecov(:rspec, tracking_config)

    result = run_command_and_expect_success("bundle exec rake test")
    expect_coverage_report_generated(result)
    expect_tracked_file_percents(html_report_data, framework_specific: 75.00)

    result = run_command_and_expect_success(sorted_rspec_command)
    expect_coverage_report_generated(result)
    expect(result.output).to include("Coverage report generated for RSpec, Unit Tests")

    data = html_report_data
    expect(data.fetch("meta").fetch("command_name")).to eq("RSpec, Unit Tests")
    expect(reported_total_percent(data)).to eq(79.16)
    expect_tracked_file_percents(data, framework_specific: 87.50)
  end

  it "keeps never-loaded tracked files when resultsets are collated by a separate step" do
    configure_simplecov(:test_unit, tracking_config)

    expect_coverage_report_generated(run_command_and_expect_success("bundle exec rake part1"))
    stash_resultset(1)
    expect_coverage_report_generated(run_command_and_expect_success("bundle exec rake part2"))
    stash_resultset(2)

    result = run_command_and_expect_success("bundle exec rake collate")
    expect_coverage_report_generated(result)

    data = html_report_data
    expect(reported_total_percent(data)).to eq(77.08)
    expect_tracked_file_percents(data, framework_specific: 75.00)
  end
end
