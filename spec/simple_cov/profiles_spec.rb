# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::Profiles, mutant_expression: ["SimpleCov::Profiles*", "SimpleCov::Configuration*"] do
  subject(:profiles) { described_class.new }

  describe "#define" do
    it "stores a profile by symbolic name" do
      profiles.define("foo") { add_filter "x" }
      expect(profiles[:foo]).to be_a(Proc)
    end

    it "raises when defining a duplicate name, naming the profile" do
      profiles.define("foo") { add_filter "x" }
      expect { profiles.define("foo") { add_filter "y" } }
        .to raise_error(SimpleCov::ConfigurationError, "SimpleCov Profile 'foo' is already defined")
    end
  end

  describe "#fetch_proc" do
    it "raises with a clear message when no such profile exists and autoload turns up nothing" do
      expect { profiles.fetch_proc("__nope__") }
        .to raise_error(SimpleCov::ConfigurationError, "Could not find SimpleCov Profile called '__nope__'")
    end

    it "answers the profile that was defined under that name" do
      block = proc { add_filter "x" }
      profiles.define("foo", &block)

      expect(profiles.fetch_proc("foo")).to be(block)
    end

    it "answers the profile under the symbolic form of that name" do
      block = proc { add_filter "x" }
      profiles.define("foo", &block)

      expect(profiles.fetch_proc(:foo)).to be(block)
    end

    context "when the name has to be autoloaded" do
      let(:registry) { described_class.new }
      let(:block) { proc { add_filter "x" } }

      it "gives up on a name neither place carries" do
        allow(registry).to receive(:require).and_raise(LoadError)

        expect { registry.fetch_proc("__nope__") }.to raise_error(SimpleCov::ConfigurationError)
      end

      it "looks for a bundled profile of the name" do
        allow(registry).to receive(:require).and_raise(LoadError)
        suppress(SimpleCov::ConfigurationError) { registry.fetch_proc("__nope__") }

        expect(registry).to have_received(:require).with("simplecov/profiles/__nope__")
      end

      it "looks for a plugin gem of the name" do
        allow(registry).to receive(:require).and_raise(LoadError)
        suppress(SimpleCov::ConfigurationError) { registry.fetch_proc("__nope__") }

        expect(registry).to have_received(:require).with("simplecov-profile-__nope__")
      end

      it "answers a profile it already has without loading" do
        allow(registry).to receive(:require)
        registry.define("known", &block)

        expect(registry.fetch_proc("known")).to be(block)
      end

      it "loads nothing for a profile it already has" do
        allow(registry).to receive(:require)
        registry.define("known", &block)
        registry.fetch_proc("known")

        expect(registry).not_to have_received(:require)
      end

      it "answers a profile the autoload defined" do
        allow(registry).to receive(:require) { |_| registry[:late] = block }

        expect(registry.fetch_proc("late")).to be(block)
      end

      it "answers a profile the bundled autoload defined" do
        allow(registry).to receive(:require).with("simplecov/profiles/bundled") { |_| registry[:bundled] = block }

        expect(registry.fetch_proc("bundled")).to be(block)
      end

      it "asks the plugin gems only for a name the bundled profiles do not carry" do
        allow(registry).to receive(:require).with("simplecov/profiles/bundled") { |_| registry[:bundled] = block }
        registry.fetch_proc("bundled")

        expect(registry).not_to have_received(:require).with("simplecov-profile-bundled")
      end
    end
  end

  describe "the bundled 'strict' profile (#1061)" do
    around do |example|
      prev_criteria = SimpleCov.coverage_criteria.dup
      prev_min = SimpleCov.minimum_coverage.dup
      prev_eval = SimpleCov.instance_variable_get(:@coverage_for_eval_enabled)
      example.run
    ensure
      SimpleCov.clear_coverage_criteria
      prev_criteria.each { |c| SimpleCov.enable_coverage(c) }
      SimpleCov.minimum_coverage(prev_min.empty? ? {} : prev_min)
      SimpleCov.instance_variable_set(:@coverage_for_eval_enabled, prev_eval)
    end

    context "when the runtime measures every criterion" do
      before do
        allow(Coverage).to receive(:supported?).and_call_original
        allow(Coverage).to receive(:supported?).with(:branches).and_return(true)
        allow(Coverage).to receive(:supported?).with(:methods).and_return(true)
      end

      it "enables every criterion" do
        SimpleCov.load_profile "strict"

        expect(SimpleCov.coverage_criteria).to include(:line, :branch, :method)
      end

      it "pins every criterion to 100%" do
        SimpleCov.load_profile "strict"

        expect(SimpleCov.minimum_coverage).to eq(line: 100, branch: 100, method: 100)
      end
    end

    context "when the runtime measures neither branches nor methods, like JRuby" do
      before do
        allow(Coverage).to receive(:supported?).and_call_original
        allow(Coverage).to receive(:supported?).with(:branches).and_return(false)
        allow(Coverage).to receive(:supported?).with(:methods).and_return(false)
        SimpleCov.clear_coverage_criteria
        SimpleCov.minimum_coverage({})
      end

      it "enables only line coverage, so Coverage.start is not asked for the rest" do
        SimpleCov.load_profile "strict"

        expect(SimpleCov.coverage_criteria).to eq(Set[:line])
      end

      it "pins only line coverage to 100%" do
        SimpleCov.load_profile "strict"

        expect(SimpleCov.minimum_coverage).to eq(line: 100)
      end
    end

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

    it "leaves a file outside the test directories out of the test_frameworks profile" do
      config.load_profile(:test_frameworks)

      expect(filtered?(config, "foo.rb")).to be_falsey
    end

    it "filters test/ in the test_frameworks profile" do
      config.load_profile(:test_frameworks)

      expect(filtered?(config, "test/foo.rb")).to be_truthy
    end

    it "filters spec/ in the test_frameworks profile" do
      config.load_profile(:test_frameworks)

      expect(filtered?(config, "spec/bar.rb")).to be_truthy
    end

    it "leaves app/ out of the rails profile" do
      config.load_profile(:rails)

      expect(filtered?(config, "app/models/user.rb")).to be_falsey
    end

    it "filters db/ in the rails profile" do
      config.load_profile(:rails)

      expect(filtered?(config, "db/schema.rb")).to be_truthy
    end

    it "filters config/ in the rails profile" do
      config.load_profile(:rails)

      expect(filtered?(config, "config/environment.rb")).to be_truthy
    end

    it "declares the files every test of a Rails app reads as global in the rails profile" do
      config.load_profile(:rails)

      expect(config.global_files).to eq(
        %w[config/**/* db/schema.rb db/structure.sql Gemfile.lock test/test_helper.rb test/fixtures/**/*
          spec/spec_helper.rb spec/rails_helper.rb spec/support/**/*]
      )
    end

    it "alphabetizes the rails profile's groups by name" do
      config.load_profile(:rails)

      expect(config.groups.keys).to eq(config.groups.keys.sort)
    end

    it "enables subprocess support in the rails profile (covers parallelize forks)" do
      config.load_profile(:rails)
      expect(config.enabled_for_subprocesses?).to be true
    end
  end
end
