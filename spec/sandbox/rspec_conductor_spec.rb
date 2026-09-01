# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "rspec-conductor integration", :sandbox do
  before do
    skip "rspec-conductor forks its workers" unless Process.respond_to?(:fork)
    setup_project("parallel_tests", gemfile_from: "rspec_conductor")
    install_dependencies
  end

  def wait_for_file(relative_path, timeout: 30)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    sleep 0.1 until file_exist?(relative_path) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  end

  def expect_report_files
    expect(file_exist?("coverage/index.html")).to be(true)
    expect(file_exist?("coverage/.resultset.json")).to be(true)
  end

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

  def configure_conductor_coverage(*settings)
    configure_simplecov(:rspec, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        parallel_wait_timeout 120
        #{settings.join("\n    ")}
      end
    RUBY
  end

  def run_conductor(*flags)
    command = "bundle exec rspec-conductor --workers 2 #{flags.join(" ")} spec".squeeze(" ")
    2.times do
      FileUtils.rm_rf(File.join(sandbox_dir, "coverage"))
      run_command_and_expect_success(command, timeout: 240)
      wait_for_file("coverage/.last_run.json")
      return if file_exist?("coverage/index.html")
    end

    raise "`#{command}` merged no report in two runs. Resultset held: #{conductor_worker_summary}"
  end

  def conductor_worker_summary
    return "no resultset at all" unless file_exist?("coverage/.resultset.json")

    resultset_json.map { |name, data| "#{name} (#{data.fetch("coverage", {}).size} files)" }.join(", ")
  end

  it "produces the normal-run results through rspec-conductor" do
    configure_conductor_coverage
    run_conductor
    expect_report_files
    expect_line_results(html_report_data)
  end

  it "merges just the same with --first-is-1" do
    configure_conductor_coverage
    run_conductor("--first-is-1")
    expect_report_files
    expect_line_results(html_report_data)
  end

  it "reports branch coverage" do
    configure_conductor_coverage("enable_coverage :branch")

    run_conductor
    expect_report_files

    data = html_report_data
    expect_line_results(data)
    files = data.fetch("coverage").values
    expect(files.sum { |file| file.fetch("covered_branches") }).to eq(4)
    expect(files.sum { |file| file.fetch("total_branches") }).to eq(8)
    expect(reported_file_percents(data, criterion: "branches")).to eq(
      "lib/all.rb" => 100.00,
      "lib/a.rb" => 50.00,
      "lib/b.rb" => 100.00,
      "lib/c.rb" => 50.00,
      "lib/d.rb" => 50.00
    )
  end

  it "enforces coverage thresholds against the merged result, not per worker" do
    configure_conductor_coverage("minimum_coverage 81.48")

    run_conductor
    wait_for_file("coverage/.last_run.json")
    expect(read_file("coverage/.last_run.json")).to include("81.48")
    expect_line_results(html_report_data)
  end
end
