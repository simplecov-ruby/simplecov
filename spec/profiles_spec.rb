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
    let(:config_class) { Class.new { include SimpleCov::Configuration } }
    let(:config) { config_class.new }

    around do |example|
      prev_criteria = SimpleCov.coverage_criteria.dup
      prev_min      = SimpleCov.minimum_coverage.dup
      example.run
    ensure
      SimpleCov.clear_coverage_criteria
      prev_criteria.each { |c| SimpleCov.enable_coverage(c) }
      SimpleCov.minimum_coverage(prev_min.empty? ? {} : prev_min)
    end

    it "enables every supported criterion and pins each to 100%" do
      SimpleCov.load_profile "strict"

      expect(SimpleCov.coverage_criteria).to include(:line)
      expect(SimpleCov.minimum_coverage[:line]).to eq(100)

      if SimpleCov.branch_coverage_supported?
        expect(SimpleCov.coverage_criteria).to include(:branch)
        expect(SimpleCov.minimum_coverage[:branch]).to eq(100)
      end

      if SimpleCov.method_coverage_supported?
        expect(SimpleCov.coverage_criteria).to include(:method)
        expect(SimpleCov.minimum_coverage[:method]).to eq(100)
      end
    end

    it "skips branch/method when the runtime doesn't support them" do
      # Stub support negative for both — the profile should still load
      # without raising and only pin line at 100%.
      allow(SimpleCov).to receive_messages(branch_coverage_supported?: false, method_coverage_supported?: false)
      SimpleCov.load_profile "strict"

      expect(SimpleCov.minimum_coverage).to eq(line: 100)
    end
  end
end
