# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# Files matched by `cover` but never loaded are simulated once, at
# the merge, rather than by every process that writes a resultset. The
# processes that ran the suite record which files they were told to
# track, so a separate `SimpleCov.collate` step still reports the ones
# nobody loaded even though it never saw the `cover` configuration
# itself.
RSpec.describe "cover across merges and collation", :sandbox do
  before { setup_project("faked_project") }

  let(:tracking_config) do
    <<~RUBY
      require 'simplecov'
      SimpleCov.start do
        cover "lib/**/*.rb"
      end
    RUBY
  end

  # The unit-test suite's percents; framework_specific.rb rises to 87.50
  # once the rspec suite's result is merged in.
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

  # The same injection, reached through `merged_result` rather than
  # `collate`: two suites merging in-process, where the cover
  # must survive the merge exactly once rather than being simulated by
  # each suite in turn.
  it "keeps never-loaded cover when two suites merge in one process" do
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

  it "keeps never-loaded cover when resultsets are collated by a separate step" do
    configure_simplecov(:test_unit, tracking_config)

    expect_coverage_report_generated(run_command_and_expect_success("bundle exec rake part1"))
    stash_resultset(1)
    expect_coverage_report_generated(run_command_and_expect_success("bundle exec rake part2"))
    stash_resultset(2)

    # The `collate` rake task calls `SimpleCov.collate` with no
    # configuration block, and the project has no `.simplecov`, so this
    # process knows nothing about `cover`. untested_class.rb
    # reaches the report only because the resultsets carry the paths
    # their processes were told to track.
    result = run_command_and_expect_success("bundle exec rake collate")
    expect_coverage_report_generated(result)

    data = html_report_data
    expect(reported_total_percent(data)).to eq(77.08)
    expect_tracked_file_percents(data, framework_specific: 75.00)
  end
end
