# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::Profiles do
  subject(:profiles) { described_class.new }

  describe "#define" do
    it "stores a profile by symbolic name" do
      profiles.define("foo") { add_filter "x" }
      expect(profiles[:foo]).to be_a(Proc)
    end

    it "raises when defining a duplicate name" do
      profiles.define("foo") { add_filter "x" }
      expect { profiles.define("foo") { add_filter "y" } }
        .to raise_error(SimpleCov::ConfigurationError, /already defined/)
    end
  end

  describe "#fetch_proc" do
    it "raises with a clear message when no such profile exists and autoload turns up nothing" do
      expect { profiles.fetch_proc("__nope__") }
        .to raise_error(SimpleCov::ConfigurationError, /Could not find SimpleCov Profile/)
    end
  end

  describe "the bundled 'strict' profile (#1061)" do
    around do |example|
      prev_criteria = SimpleCov.coverage_criteria.dup
      prev_min      = SimpleCov.minimum_coverage.dup
      example.run
    ensure
      SimpleCov.clear_coverage_criteria
      prev_criteria.each { |c| SimpleCov.enable_coverage(c) }
      SimpleCov.minimum_coverage(prev_min.empty? ? {} : prev_min)
    end

    # No engine-conditional logic in the profile itself — every clause
    # runs unconditionally, and CoverageViolations skips threshold
    # lookups for criteria the runtime didn't measure. So on JRuby the
    # branch / method thresholds silently no-op and only :line is
    # enforced at check time.
    it "enables every criterion and pins each to 100%" do
      SimpleCov.load_profile "strict"

      expect(SimpleCov.coverage_criteria).to include(:line, :branch, :method)
      expect(SimpleCov.minimum_coverage).to eq(line: 100, branch: 100, method: 100)
    end
  end
end
