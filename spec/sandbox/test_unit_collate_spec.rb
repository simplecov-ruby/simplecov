# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "collating stored resultsets", :sandbox do
  before { setup_project("faked_project") }

  def stash_resultset(index)
    FileUtils.mv(
      File.join(sandbox_dir, "coverage/.resultset.json"),
      File.join(sandbox_dir, "coverage/resultset#{index}.json")
    )
    FileUtils.rm(File.join(sandbox_dir, "coverage/index.html"))
  end

  def store_partial_resultsets
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start
    RUBY

    %w[part1 part2].each_with_index do |task, index|
      expect_coverage_report_generated(run_command_and_expect_success("bundle exec rake #{task}"))
      stash_resultset(index + 1)
    end
  end

  def expect_collated_report(data)
    expect(reported_total_percent(data)).to eq(88.09)
    expect(data.fetch("coverage").size).to eq(4)
    expect(reported_file_percents(data)).to eq(
      "lib/faked_project.rb" => 100.00,
      "lib/faked_project/some_class.rb" => 80.00,
      "lib/faked_project/framework_specific.rb" => 75.00,
      "lib/faked_project/meta_magic.rb" => 100.00
    )
    expect(data.dig("meta", "command_name")).to include("Unit Tests")
  end

  it "collates the parts into one report" do
    store_partial_resultsets

    result = run_command_and_expect_success("bundle exec rake collate")
    expect_coverage_report_generated(result)
    expect_collated_report(html_report_data)
  end
end
