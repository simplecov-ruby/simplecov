# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# rspec-conductor is a queue-based parallel spec runner. It forks its
# workers from a server process, gives each worker one spec file at a
# time, and marks every worker with the parallel_tests environment
# convention: TEST_ENV_NUMBER per worker plus PARALLEL_TEST_GROUPS for
# the worker count (since rspec-conductor 1.0.7). SimpleCov's generic
# parallel adapter picks that up without any configuration, so each
# worker records under a unique suite name and the first worker waits
# for its siblings and builds the merged report.
#
# `--workers 2` pins the worker count for a fast, deterministic run.
# Workers that get no spec file still load spec_helper at spawn and
# record an empty resultset, so the merged totals come out the same
# either way.
#
# The examples assert on the generated report files rather than on the
# usual "Coverage report generated" line: the conductor server closes
# each worker's output pipes once the worker has sent its run summary,
# before at_exit hooks run, so nothing SimpleCov prints from at_exit
# can reach the output. The report itself is written fine.
RSpec.describe "rspec-conductor integration", :sandbox do
  before do
    skip "rspec-conductor forks its workers" unless Process.respond_to?(:fork)
    setup_project("parallel_tests", gemfile_from: "rspec_conductor")
    install_dependencies
  end

  # Command success need not mean the artifacts are already on disk: the
  # server stops forwarding a worker's output the moment its run summary
  # arrives, and its shutdown ordering around at_exit is not ours to
  # control. The sibling wait configured below runs inside the command
  # though, so by the time it returns the reporter has either written the
  # report or given up, and this only has to cover the gap between its last
  # write and the server's own exit. `.last_run.json` lands last in the
  # at_exit sequence (after the HTML report and the resultset), so its
  # appearance means everything the assertions read is on disk.
  def wait_for_file(relative_path, timeout: 30)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    sleep 0.1 until file_exist?(relative_path) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  end

  def expect_report_files
    expect(file_exist?("coverage/index.html")).to be(true)
    expect(file_exist?("coverage/.resultset.json")).to be(true)
  end

  # The same figures the parallel_tests fixture produces under plain
  # rspec (see parallel_tests_spec.rb).
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

  # Every example raises how long the reporting worker waits for its
  # sibling's resultset. A saturated CI runner routinely leaves that sibling
  # writing well past the 60 second default, and expiry is not a slow report
  # but no report at all: SimpleCov skips result processing outright once the
  # wait gives up (see `ready_to_process_results?`), so the artifacts these
  # examples read never appear and waiting on them cannot help.
  def configure_conductor_coverage(*settings)
    configure_simplecov(:rspec, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        parallel_wait_timeout 120
        #{settings.join("\n    ")}
      end
    RUBY
  end

  # That wait runs inside the command rather than after it, because the
  # server waits on worker exit, so the command budget has to clear the 120
  # second wait with room for the merge and the report on top.
  #
  # A worker starved or killed outright on a saturated runner never writes
  # its resultset at all, and no wait can conjure one: the reporting worker
  # abandons the merged report rather than publish partial totals, which is
  # the runner's doing rather than SimpleCov's. It is rare and it is not
  # sticky, so give the run one clean attempt more, and say what the
  # resultset actually held if a second worker goes missing too.
  def run_conductor(*flags)
    command = "bundle exec rspec-conductor --workers 2 #{flags.join(' ')} spec".squeeze(" ")
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

    resultset_json.map { |name, data| "#{name} (#{data.fetch('coverage', {}).size} files)" }.join(", ")
  end

  it "produces the normal-run results through rspec-conductor" do
    configure_conductor_coverage
    run_conductor
    expect_report_files
    expect_line_results(html_report_data)
  end

  # In default mode the first worker's TEST_ENV_NUMBER is "" like
  # parallel_tests. With --first-is-1 it is "1" instead, and the workers
  # count 1..N. Both spellings must resolve to a single reporting worker.
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

  # Each worker on its own covers only a slice of the project, so a
  # threshold check against a single worker's partial result would fail.
  # Only the reporting worker, after merging every sibling's slice, may
  # enforce it. The conductor server swallows a worker's at_exit output
  # and ignores its exit status once its run summary is in, so asserting
  # on output or exit code proves nothing here. Instead this leans on
  # .last_run.json, which SimpleCov writes only when the threshold check
  # passes: finding it filled with the merged 81.48 shows the check ran
  # against the merged result, where any single worker's slice would
  # have failed and left the file unwritten.
  it "enforces coverage thresholds against the merged result, not per worker" do
    configure_conductor_coverage("minimum_coverage 81.48")

    run_conductor
    wait_for_file("coverage/.last_run.json")
    expect(read_file("coverage/.last_run.json")).to include("81.48")
    expect_line_results(html_report_data)
  end
end
