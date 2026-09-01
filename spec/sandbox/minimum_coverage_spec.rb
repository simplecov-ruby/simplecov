# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "minimum coverage enforcement", :sandbox do
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

  describe "a minimum well above the actual coverage" do
    let!(:result) { run_with_thresholds("minimum_coverage 90") }

    it "fails the run" do
      expect(result.exit_status).not_to eq(0)
    end

    it "says how far below it fell" do
      expect(result.output).to include("Line coverage (88.09%) is below the expected minimum coverage (90.00%).")
    end

    it "exits 2" do
      expect(result.output).to include("SimpleCov failed with exit 2")
    end
  end

  describe "a minimum 0.01% above the actual coverage" do
    let!(:result) { run_with_thresholds("minimum_coverage 88.10") }

    it "fails the run" do
      expect(result.exit_status).not_to eq(0)
    end

    it "says how far below it fell" do
      expect(result.output).to include("Line coverage (88.09%) is below the expected minimum coverage (88.10%).")
    end

    it "exits 2" do
      expect(result.output).to include("SimpleCov failed with exit 2")
    end
  end

  describe "a minimum exactly at the actual coverage" do
    let!(:result) { run_with_thresholds("minimum_coverage 88.09") }

    it "passes" do
      expect(result.exit_status).to eq(0)
    end
  end

  describe "line and branch minimums together" do
    let!(:result) do
      run_with_thresholds(<<~RUBY.strip)
        enable_coverage :branch
        minimum_coverage line: 90, branch: 80
      RUBY
    end

    it "fails the run" do
      expect(result.exit_status).not_to eq(0)
    end

    it "announces the line shortfall" do
      expect(result.output).to include("Line coverage (88.09%) is below the expected minimum coverage (90.00%).")
    end

    it "announces the branch shortfall" do
      expect(result.output).to include("Branch coverage (50.00%) is below the expected minimum coverage (80.00%).")
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
        minimum_coverage 80
      RUBY
    end

    it "fails the run" do
      expect(result.exit_status).not_to eq(0)
    end

    it "announces the branch shortfall" do
      expect(result.output).to include("Branch coverage (50.00%) is below the expected minimum coverage (80.00%).")
    end

    it "says nothing about lines" do
      expect(result.output).not_to include("Line coverage (")
    end

    it "exits 2" do
      expect(result.output).to include("SimpleCov failed with exit 2")
    end
  end
end
