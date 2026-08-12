# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# Coverage should include code run by forked subprocesses. The
# subprocesses fixture ships a .simplecov enabling subprocess tracking
# and filtering everything but lib/subprocesses.rb, whose #run forks a
# child that calls a method only the child covers.
RSpec.describe "coverage for subprocesses", :sandbox do
  before do
    skip "the fixture forks subprocesses" unless Process.respond_to?(:fork)
    setup_project("subprocesses")
  end

  def expect_fully_covered_single_file(data)
    expect(reported_total_percent(data)).to eq(100.00)
    expect(data.fetch("coverage").size).to eq(1)
  end

  it "sees the line only the subprocess runs" do
    result = run_command_and_expect_success("bundle exec rspec spec/simple_spec.rb")
    expect_coverage_report_generated(result)
    expect_fully_covered_single_file(html_report_data)
  end

  it "runs the at_fork proc in the child and merges its results" do
    write_file(".simplecov", <<~RUBY)
      SimpleCov.merge_subprocesses true
      SimpleCov.command_name "parent process name"
      SimpleCov.at_fork do |_pid|
        SimpleCov.command_name "child process name"
        SimpleCov.start
      end
    RUBY

    result = run_command_and_expect_success("bundle exec rspec spec/simple_spec.rb")
    expect_coverage_report_generated(result)
    expect(result.output).to include("Coverage report generated for child process name, parent process name")

    data = html_report_data
    expect_fully_covered_single_file(data)
    expect(data.dig("meta", "command_name")).to eq("child process name, parent process name")
  end

  # Reproduces #1227: a parent that hands its report to an external
  # at_exit owner (what the Minitest autorun deferral and the minitest
  # plugin do) passes external_at_exit = true into forked children,
  # where the deferral target can never fire. The child must reset the
  # inherited state and store its own resultset, or its coverage
  # silently vanishes.
  def write_deferring_parent_config
    write_file(".simplecov", <<~RUBY)
      SimpleCov.merge_subprocesses true
      SimpleCov.command_name "parent process name"
      SimpleCov.skip /command/
      SimpleCov.skip /spawn/
    RUBY
  end

  def write_externally_deferred_parent
    write_deferring_parent_config
    write_file("external_exit.rb", <<~RUBY)
      require "simplecov"
      SimpleCov.start
      SimpleCov.external_at_exit = true
      require_relative "lib/subprocesses"
      Subprocesses.new.run
      SimpleCov.at_exit_behavior
    RUBY
  end

  it "merges forked children when the parent defers its report externally" do
    write_externally_deferred_parent

    result = run_command_and_expect_success("bundle exec ruby external_exit.rb")
    expect_coverage_report_generated(result)
    expect(result.output)
      .to include("Coverage report generated for parent process name, parent process name (subprocess: 1)")

    data = html_report_data
    expect_fully_covered_single_file(data)
    expect(data.dig("meta", "command_name")).to eq("parent process name, parent process name (subprocess: 1)")
  end

  # The documented .simplecov_spawn pattern: a spawned (not forked)
  # command loads it via `ruby -r./.simplecov_spawn` to start coverage
  # under the parent's at_fork proc.
  it "covers spawned commands through .simplecov_spawn" do
    result = run_command_and_expect_success("bundle exec rspec spec/spawn_spec.rb")
    expect_coverage_report_generated(result)
    expect_fully_covered_single_file(html_report_data)
  end
end
