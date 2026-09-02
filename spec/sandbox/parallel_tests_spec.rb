# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "parallel_tests integration", :sandbox do
  before do
    skip "requires POSIX process forking" unless Process.respond_to?(:fork)
    setup_project("parallel_tests")
    install_dependencies
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

  describe "a minimum coverage the whole suite meets" do
    let!(:result) do
      configure_simplecov(:rspec, <<~RUBY)
        require 'simplecov'
        SimpleCov.start do
          minimum_coverage 81.48
        end
      RUBY
      run_command_and_expect_success("bundle exec parallel_rspec -n 2 spec", timeout: 120)
    end

    it "does not print coverage violations from individual workers" do
      expect(result.output).not_to match(/cover.+below.+minimum/)
    end
  end

  describe "turbo-style external collation" do
    let(:collate_script) do
      %(SimpleCov.collate(Dir["coverage/turbo_tests/*/.resultset.json"]) { minimum_coverage 81.48 })
    end
    let(:worker_groups) { {"1" => "spec/a_spec.rb spec/b_spec.rb", "2" => "spec/c_spec.rb spec/d_spec.rb"} }
    let!(:worker_outputs) do
      configure_simplecov(:rspec, <<~RUBY)
        require 'simplecov'
        SimpleCov.start do
          minimum_coverage 81.48
          coverage_dir File.join("coverage", "turbo_tests", ENV.fetch("TEST_ENV_NUMBER"))
          command_name "rspec-\#{ENV.fetch("TEST_ENV_NUMBER")}"
          finalize_merge false
        end
      RUBY
      worker_groups.map do |worker, files|
        env = {"TEST_ENV_NUMBER" => worker, "PARALLEL_TEST_GROUPS" => "2"}
        run_command_and_expect_success("bundle exec rspec #{files}", env: env).output
      end
    end
    let(:collated) { run_command_and_expect_success(%(bundle exec ruby -e 'require "simplecov"; #{collate_script}')) }

    it "fails no worker" do
      expect(worker_outputs.grep(/SimpleCov failed with exit 2/)).to be_empty
    end

    it "prints no worker coverage violation" do
      expect(worker_outputs.grep(/cover.+below.+minimum/)).to be_empty
    end

    it "generates a report from the collated resultsets" do
      expect(collated.output).to include("Coverage report generated")
    end

    it "does not fail the collation" do
      expect(collated.output).not_to include("SimpleCov failed with exit 2")
    end
  end
end
