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
      prev_eval     = SimpleCov.instance_variable_get(:@coverage_for_eval_enabled)
      example.run
    ensure
      SimpleCov.clear_coverage_criteria
      prev_criteria.each { |c| SimpleCov.enable_coverage(c) }
      SimpleCov.minimum_coverage(prev_min.empty? ? {} : prev_min)
      SimpleCov.instance_variable_set(:@coverage_for_eval_enabled, prev_eval)
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

    # `:eval` widens the strict universe to include code passed through
    # `Kernel#eval` (ERB templates, etc.) on runtimes that support it.
    # On older Rubies the toggle is silently skipped — `enable_coverage
    # :eval` would otherwise warn about missing runtime support every
    # time the profile loaded.
    it "enables :eval when the runtime supports it" do
      SimpleCov.instance_variable_set(:@coverage_for_eval_enabled, false)
      SimpleCov.load_profile "strict"

      expect(SimpleCov.coverage_for_eval_enabled?).to eq(SimpleCov.coverage_for_eval_supported?)
    end
  end

  describe "the bundled 'test_frameworks' and 'rails' profiles" do
    skip "requires the default configuration" if ENV["SIMPLECOV_NO_DEFAULTS"]

    let(:config_class) do
      Class.new do
        include SimpleCov::Configuration

        def load_profile(name)
          configure(&SimpleCov.profiles.fetch_proc(name))
        end
      end
    end

    let(:config) { config_class.new }

    def filtered?(config, filename)
      path = File.join(SimpleCov.root, filename)
      file = SimpleCov::SourceFile.new(path, [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil])
      config.filters.any? { |filter| filter.matches?(file) }
    end

    it "provides a sensible test_frameworks profile" do
      config.load_profile(:test_frameworks)
      expect(filtered?(config, "foo.rb")).to be_falsey
      expect(filtered?(config, "test/foo.rb")).to be_truthy
      expect(filtered?(config, "spec/bar.rb")).to be_truthy
    end

    it "provides a sensible rails profile" do
      config.load_profile(:rails)
      expect(filtered?(config, "app/models/user.rb")).to be_falsey
      expect(filtered?(config, "db/schema.rb")).to be_truthy
      expect(filtered?(config, "config/environment.rb")).to be_truthy
    end

    it "enables subprocess support in the rails profile (covers parallelize forks)" do
      config.load_profile(:rails)
      expect(config.enabled_for_subprocesses?).to be true
    end
  end
end
