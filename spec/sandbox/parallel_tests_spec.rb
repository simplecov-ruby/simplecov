# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# parallel_tests and SimpleCov work together out of the box and produce
# the same report a normal rspec run does. `-n 2` pins the worker count
# so it matches the number of spec files: left to default, parallel_rspec
# spawns one worker per core, and on a machine with more cores than files
# the extra workers get nothing and write no resultset. SimpleCov copes
# with that, but pinning keeps the runs fast and deterministic.
RSpec.describe "parallel_tests integration", :sandbox do
  # Worker management relies on POSIX process semantics; the cucumber
  # suite this replaces only ever ran on MRI (CI runs the plain spec
  # task on JRuby and Windows).
  before do
    skip "requires POSIX process forking" unless Process.respond_to?(:fork)
    setup_project("parallel_tests")
    install_dependencies
  end

  # The expected figures the shared parallel fixture produces, identical
  # for a parallel_rspec run and a plain rspec run.
  def expect_line_results(data)
    expect(reported_total_percent(data)).to eq(81.48)
    expect(data.fetch("coverage").size).to eq(5)
    expect(reported_file_percents(data)).to eq(
      "lib/all.rb" => 100.00,
      "lib/a.rb" => 85.71,
      "lib/b.rb" => 80.00,
      "lib/c.rb" => 75.00,
      "lib/d.rb" => 71.42
    )
  end

  # The line and branch summaries the browser steps read off the report
  # page: 22/27 lines, 4/8 branches.
  def expect_branch_summaries(data)
    files = data.fetch("coverage").values
    summed = %w[covered_lines total_lines covered_branches total_branches].to_h do |key|
      [key, files.sum { |file| file.fetch(key) }]
    end
    expect(summed).to eq(
      "covered_lines" => 22, "total_lines" => 27, "covered_branches" => 4, "total_branches" => 8
    )
  end

  def expect_branch_results(data)
    expect_line_results(data)
    expect_branch_summaries(data)
    expect(reported_file_percents(data, criterion: "branches")).to eq(
      "lib/all.rb" => 100.00,
      "lib/a.rb" => 50.00,
      "lib/b.rb" => 100.00,
      "lib/c.rb" => 50.00,
      "lib/d.rb" => 50.00
    )
  end

  def configure_line_coverage
    configure_simplecov(:rspec, <<~RUBY)
      require 'simplecov'
      SimpleCov.start
    RUBY
  end

  def configure_branch_coverage
    configure_simplecov(:rspec, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        enable_coverage :branch
      end
    RUBY
  end

  it "produces the normal-run results through parallel_rspec" do
    configure_line_coverage
    result = run_command_and_expect_success("bundle exec parallel_rspec -n 2 spec", timeout: 120)
    expect_coverage_report_generated(result)
    expect_line_results(html_report_data)
  end

  # Kept separate from the parallel run: merging of results might kick
  # in and hide a difference between the two.
  it "produces the same results through plain rspec" do
    configure_line_coverage
    result = run_command_and_expect_success("bundle exec rspec spec")
    expect_coverage_report_generated(result)
    expect_line_results(html_report_data)
  end

  it "reports branch coverage through plain rspec" do
    configure_branch_coverage
    result = run_command_and_expect_success("bundle exec rspec spec")
    expect_coverage_report_generated(result)
    expect_branch_results(html_report_data)
  end

  it "reports branch coverage through parallel_rspec" do
    configure_branch_coverage
    result = run_command_and_expect_success("bundle exec parallel_rspec -n 2 spec", timeout: 120)
    expect_coverage_report_generated(result)
    expect_branch_results(html_report_data)
  end

  it "does not print coverage violations from individual workers" do
    configure_simplecov(:rspec, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        minimum_coverage 81.48
      end
    RUBY

    result = run_command_and_expect_success("bundle exec parallel_rspec -n 2 spec", timeout: 120)
    expect(result.output).not_to match(/cover.+below.+minimum/)
  end

  # Reproduces galtzo-floss/turbo_tests2#15: worker output should not
  # include partial-result threshold failures when an explicit collate
  # step owns the final coverage report.
  it "keeps turbo-style external collation free of worker coverage violations" do
    configure_simplecov(:rspec, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        minimum_coverage 81.48
        coverage_dir File.join("coverage", "turbo_tests", ENV.fetch("TEST_ENV_NUMBER"))
        command_name "rspec-\#{ENV.fetch("TEST_ENV_NUMBER")}"
        finalize_merge false
      end
    RUBY

    worker_groups = {"1" => "spec/a_spec.rb spec/b_spec.rb", "2" => "spec/c_spec.rb spec/d_spec.rb"}
    worker_groups.each do |worker, files|
      env = {"TEST_ENV_NUMBER" => worker, "PARALLEL_TEST_GROUPS" => "2"}
      result = run_command_and_expect_success("bundle exec rspec #{files}", env: env)
      expect(result.output).not_to include("SimpleCov failed with exit 2")
      expect(result.output).not_to match(/cover.+below.+minimum/)
    end

    collate = %(SimpleCov.collate(Dir["coverage/turbo_tests/*/.resultset.json"]) { minimum_coverage 81.48 })
    result = run_command_and_expect_success("bundle exec ruby -rsimplecov -e '#{collate}'")
    expect(result.output).to include("Coverage report generated")
    expect(result.output).not_to include("SimpleCov failed with exit 2")
  end
end
