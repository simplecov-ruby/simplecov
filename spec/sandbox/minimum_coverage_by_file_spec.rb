# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "minimum coverage by file enforcement", :sandbox do
  before { setup_project("faked_project") }

  def run_with_thresholds(thresholds)
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        #{thresholds}
      end
    RUBY
    run_command("bundle exec rake test")
  end

  describe "a minimum just above the worst file" do
    let!(:result) { run_with_thresholds("minimum_coverage_by_file 75.01") }

    it "fails the run" do
      expect(result.exit_status).not_to eq(0)
    end

    it "names the file that fell short" do
      expect(result.output).to include(
        "Line coverage by file (75.00%) is below the expected minimum coverage (75.01%) " \
        "in lib/faked_project/framework_specific.rb."
      )
    end

    it "exits 2" do
      expect(result.output).to include("SimpleCov failed with exit 2")
    end
  end

  describe "a minimum exactly at the worst file" do
    let!(:result) { run_with_thresholds("minimum_coverage_by_file 75") }

    it "passes" do
      expect(result.exit_status).to eq(0)
    end
  end

  describe "line and branch minimums together" do
    let!(:result) do
      run_with_thresholds(<<~RUBY.strip)
        enable_coverage :branch
        minimum_coverage_by_file line: 90, branch: 70
      RUBY
    end

    it "fails the run" do
      expect(result.exit_status).not_to eq(0)
    end

    it "announces the line shortfall" do
      expect(result.output).to include(
        "Line coverage by file (80.00%) is below the expected minimum coverage (90.00%) " \
        "in lib/faked_project/some_class.rb."
      )
    end

    it "announces the branch shortfall" do
      expect(result.output).to include(
        "Branch coverage by file (50.00%) is below the expected minimum coverage (70.00%) " \
        "in lib/faked_project/some_class.rb."
      )
    end

    it "exits 2" do
      expect(result.output).to include("SimpleCov failed with exit 2")
    end
  end

  describe "one minimum with branch as the primary criterion" do
    let!(:result) do
      run_with_thresholds(<<~RUBY.strip)
        enable_coverage :branch
        primary_coverage :branch
        minimum_coverage_by_file 70
      RUBY
    end

    it "fails the run" do
      expect(result.exit_status).not_to eq(0)
    end

    it "announces the branch shortfall" do
      expect(result.output).to include(
        "Branch coverage by file (50.00%) is below the expected minimum coverage (70.00%) " \
        "in lib/faked_project/some_class.rb."
      )
    end

    it "says nothing about lines" do
      expect(result.output).not_to include("Line coverage (")
    end

    it "exits 2" do
      expect(result.output).to include("SimpleCov failed with exit 2")
    end
  end

  describe "a per-path override above the default" do
    let!(:result) do
      run_with_thresholds("minimum_coverage_by_file line: 70, 'lib/faked_project/framework_specific.rb' => 100")
    end

    it "fails the run" do
      expect(result.exit_status).not_to eq(0)
    end

    it "holds the named file to the override" do
      expect(result.output).to include(
        "Line coverage by file (75.00%) is below the expected minimum coverage (100.00%) " \
        "in lib/faked_project/framework_specific.rb."
      )
    end

    it "exits 2" do
      expect(result.output).to include("SimpleCov failed with exit 2")
    end
  end

  describe "a per-path override matching a directory" do
    let!(:result) do
      run_with_thresholds("minimum_coverage_by_file line: 70, 'lib/faked_project/' => 90")
    end

    it "fails the run" do
      expect(result.exit_status).not_to eq(0)
    end

    it "holds the matching files to the override" do
      expect(result.output).to include(
        "Line coverage by file (75.00%) is below the expected minimum coverage (90.00%) " \
        "in lib/faked_project/framework_specific.rb."
      )
    end

    it "exits 2" do
      expect(result.output).to include("SimpleCov failed with exit 2")
    end
  end

  describe "a per-path override that no file matches" do
    let!(:result) do
      run_with_thresholds("minimum_coverage_by_file line: 70, 'lib/nonexistent.rb' => 100")
    end

    it "passes" do
      expect(result.exit_status).to eq(0)
    end
  end
end
