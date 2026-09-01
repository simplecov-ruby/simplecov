# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "expected coverage enforcement", :sandbox do
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

  describe "coverage matching the expectation exactly" do
    let!(:result) { run_with_thresholds("expected_coverage 88.09") }

    it "passes" do
      expect(result.exit_status).to eq(0)
    end
  end

  describe "coverage below the expectation" do
    let!(:result) { run_with_thresholds("expected_coverage 90") }

    it "fails" do
      expect(result.exit_status).not_to eq(0)
    end

    it "says how far below it fell" do
      expect(result.output).to include("Line coverage (88.09%) is below the expected minimum coverage (90.00%).")
    end

    it "exits 2" do
      expect(result.output).to include("SimpleCov failed with exit 2")
    end
  end

  describe "coverage above the expectation" do
    let!(:result) { run_with_thresholds("expected_coverage 80") }

    it "fails" do
      expect(result.exit_status).not_to eq(0)
    end

    it "says how far above it rose" do
      expect(result.output).to include("Line coverage (88.09%) is above the expected maximum coverage (80.00%).")
    end

    it "suggests bumping the threshold" do
      expect(result.output).to include("Time to bump the threshold!")
    end

    it "exits 4" do
      expect(result.output).to include("SimpleCov failed with exit 4")
    end
  end

  describe "coverage above maximum_coverage on its own" do
    let!(:result) { run_with_thresholds("maximum_coverage 85") }

    it "fails" do
      expect(result.exit_status).not_to eq(0)
    end

    it "says how far above it rose" do
      expect(result.output).to include("Line coverage (88.09%) is above the expected maximum coverage (85.00%).")
    end

    it "exits 4" do
      expect(result.output).to include("SimpleCov failed with exit 4")
    end
  end
end
