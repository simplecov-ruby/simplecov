# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# Exit code should be non-zero if the overall coverage decreases by more
# than the maximum_coverage_drop threshold.
RSpec.describe "maximum coverage drop enforcement", :sandbox do
  before { setup_project("faked_project") }

  let(:uncovered_source) do
    <<~RUBY
      class UncoveredSourceCode
        def foo
          never_reached
        rescue => err
          but no one cares about invalid ruby here
        end
      end
    RUBY
  end

  let(:failing_spec) do
    <<~RUBY
      require "spec_helper"
      describe FakedProject do
        it "fails" do
          expect(false).to eq(true)
        end
      end
    RUBY
  end

  # Variant whose failing example also exercises a branch, for the
  # branch-coverage drop scenarios.
  let(:branchy_failing_spec) do
    <<~RUBY
      require "spec_helper"
      describe FakedProject do
        it "fails" do
          false ? true : expect(false).to eq(true)
        end
      end
    RUBY
  end

  def last_run_json
    JSON.parse(read_file("coverage/.last_run.json"))
  end

  # Plants a previous-run file, e.g. write_last_run("line" => 100.0).
  def write_last_run(result)
    write_file("coverage/.last_run.json", JSON.generate("result" => result))
  end

  # Shared arrangement for the branch-drop scenarios: inject the config,
  # drop line and branch coverage, and plant a 100%/100% previous run.
  def arrange_branch_drop(simplecov_config)
    configure_simplecov(:test_unit, simplecov_config)
    write_file("lib/faked_project/missed.rb", uncovered_source)
    write_file("spec/failing_spec.rb", branchy_failing_spec)
    write_last_run("line" => 100.0, "branch" => 100.0)
  end

  it "can cause spec failure when maximum_coverage_drop is configured" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        maximum_coverage_drop 3.14
      end
    RUBY

    result = run_command("bundle exec rake test")
    expect(result.exit_status).to eq(0)
    expect(file_exist?("coverage/.last_run.json")).to be(true)

    write_file("lib/faked_project/missed.rb", uncovered_source)

    result = run_command("bundle exec rake test")
    expect(result.exit_status).not_to eq(0)
    expect(result.output).to include("Line coverage has dropped by 3.31% since the last time (maximum allowed: 3.14%).")
    expect(file_exist?("coverage/.last_run.json")).to be(true)
    expect(last_run_json).to eq("result" => {"line" => 88.09})
  end

  it "updates the resultset when maximum_coverage_drop is not configured" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
      end
    RUBY

    result = run_command("bundle exec rake test")
    expect(result.exit_status).to eq(0)
    expect(file_exist?("coverage/.last_run.json")).to be(true)
    expect(last_run_json).to eq("result" => {"line" => 88.09})

    write_file("lib/faked_project/missed.rb", uncovered_source)

    result = run_command("bundle exec rake test")
    expect(result.exit_status).to eq(0)
    expect(file_exist?("coverage/.last_run.json")).to be(true)
    expect(last_run_json).to eq("result" => {"line" => 84.78})
  end

  it "does not update the resultset on test failures" do
    configure_simplecov(:rspec, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        add_group 'Libs', 'lib/faked_project/'
        add_filter '/spec/'
        maximum_coverage_drop 0
      end
    RUBY

    write_file("lib/faked_project/missed.rb", uncovered_source)
    write_file("spec/failing_spec.rb", failing_spec)
    write_last_run("line" => 100.0)

    result = run_command(sorted_rspec_command)
    expect(result.exit_status).to eq(1)
    expect(file_exist?("coverage/.last_run.json")).to be(true)
    expect(last_run_json).to eq("result" => {"line" => 100.0})
  end

  it "still works when the previous last_run file has legacy covered_percent" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        maximum_coverage_drop 0
      end
    RUBY
    write_last_run("covered_percent" => 88.09)

    result = run_command("bundle exec rake test")
    expect(result.exit_status).to eq(0)
    expect(file_exist?("coverage/.last_run.json")).to be(true)
    expect(last_run_json).to eq("result" => {"line" => 88.09})
  end

  it "does not update a legacy covered_percent last_run file when we fail" do
    configure_simplecov(:rspec, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        add_group 'Libs', 'lib/faked_project/'
        add_filter '/spec/'
        maximum_coverage_drop 0
      end
    RUBY

    write_file("lib/faked_project/missed.rb", uncovered_source)
    write_file("spec/failing_spec.rb", failing_spec)
    write_last_run("covered_percent" => 100.0)

    result = run_command(sorted_rspec_command)
    expect(result.exit_status).to eq(1)
    expect(file_exist?("coverage/.last_run.json")).to be(true)
    expect(last_run_json).to eq("result" => {"covered_percent" => 100.0})
  end

  it "works together with branch coverage and line coverage, announcing both failures" do
    arrange_branch_drop(<<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        enable_coverage :branch
        maximum_coverage_drop line: 0, branch: 0
      end
    RUBY

    result = run_command("bundle exec rake test")
    expect(result.exit_status).not_to eq(0)
    expect(result.output)
      .to include("Line coverage has dropped by 15.22% since the last time (maximum allowed: 0.00%).")
    expect(result.output)
      .to include("Branch coverage has dropped by 50.00% since the last time (maximum allowed: 0.00%).")
    expect(result.output).to include("SimpleCov failed with exit 3")
  end

  it "can set branch as primary coverage and it will fail if branch is below maximum coverage drop" do
    arrange_branch_drop(<<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        enable_coverage :branch
        primary_coverage :branch
        maximum_coverage_drop 0
      end
    RUBY

    result = run_command("bundle exec rake test")
    expect(result.exit_status).not_to eq(0)
    expect(result.output).not_to include("Line coverage has dropped")
    expect(result.output)
      .to include("Branch coverage has dropped by 50.00% since the last time (maximum allowed: 0.00%).")
    expect(result.output).to include("SimpleCov failed with exit 3")
  end

  it "announces both criteria with branch as primary coverage when both drop thresholds are configured" do
    arrange_branch_drop(<<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        enable_coverage :branch
        primary_coverage :branch
        maximum_coverage_drop line: 0, branch: 0
      end
    RUBY

    result = run_command("bundle exec rake test")
    expect(result.exit_status).not_to eq(0)
    expect(result.output)
      .to include("Branch coverage has dropped by 50.00% since the last time (maximum allowed: 0.00%).")
    expect(result.output)
      .to include("Line coverage has dropped by 15.22% since the last time (maximum allowed: 0.00%).")
    expect(result.output).to include("SimpleCov failed with exit 3")
  end
end
