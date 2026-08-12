# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# SimpleCov.collate with processes: > 1 must produce the same report a
# single-process collate does — fanning out changes how the resultsets
# are folded, not what they fold to. The figures below are identical to
# the ones in test_unit_collate_spec.rb on purpose.
RSpec.describe "parallel collate", :sandbox do
  # The fan-out forks worker processes, which the cucumber suite this
  # replaces only ever exercised on MRI (CI runs the plain spec task on
  # JRuby and Windows).
  before do
    skip "SimpleCov.collate processes: forks workers" unless Process.respond_to?(:fork)
    setup_project("faked_project")
  end

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
    # "Unit Tests, Unit Tests": collate joins each part's suite name
    # (see test_unit_collate_spec.rb).
    expect(data.dig("meta", "command_name")).to include("Unit Tests")
  end

  it "produces the single-process collate report" do
    store_partial_resultsets

    result = run_command_and_expect_success("bundle exec rake parallel_collate")
    expect_coverage_report_generated(result)
    expect_collated_report(html_report_data)
  end
end
