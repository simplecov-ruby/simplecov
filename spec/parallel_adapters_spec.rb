# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ParallelAdapters do
  # Reset the registry / current selection / env between examples.
  # Nested describe blocks rebind `described_class` to their target
  # adapter, so the around block addresses the registry by its full
  # constant name instead of relying on `described_class` (which would
  # call `reset_current!` on whichever adapter is in scope and explode).
  # rubocop:disable RSpec/DescribedClass
  around do |example|
    prev_adapters = SimpleCov::ParallelAdapters.instance_variable_get(:@adapters)&.dup
    prev_test_env_number = ENV.fetch("TEST_ENV_NUMBER", nil)
    prev_parallel_test_groups = ENV.fetch("PARALLEL_TEST_GROUPS", nil)
    prev_parallel_pid_file = ENV.fetch("PARALLEL_PID_FILE", nil)

    SimpleCov::ParallelAdapters.instance_variable_set(:@adapters, nil)
    SimpleCov::ParallelAdapters.reset_current!
    example.run
  ensure
    SimpleCov::ParallelAdapters.instance_variable_set(:@adapters, prev_adapters)
    SimpleCov::ParallelAdapters.reset_current!
    ENV["TEST_ENV_NUMBER"] = prev_test_env_number
    ENV["PARALLEL_TEST_GROUPS"] = prev_parallel_test_groups
    ENV["PARALLEL_PID_FILE"] = prev_parallel_pid_file
  end
  # rubocop:enable RSpec/DescribedClass

  describe ".adapters" do
    it "ships ParallelTestsAdapter first and GenericAdapter second" do
      expect(described_class.adapters).to eq([
                                               SimpleCov::ParallelAdapters::ParallelTestsAdapter,
                                               SimpleCov::ParallelAdapters::GenericAdapter
                                             ])
    end
  end

  describe ".register" do
    let(:custom_adapter) do
      Class.new(SimpleCov::ParallelAdapters::Base) do
        # All four methods default to no-op via the Base superclass;
        # this fake adapter is intentionally inactive.
      end
    end

    it "prepends the adapter so user adapters take precedence" do
      described_class.register(custom_adapter)
      expect(described_class.adapters.first).to equal(custom_adapter)
    end

    it "is idempotent — registering twice doesn't duplicate" do
      described_class.register(custom_adapter)
      described_class.register(custom_adapter)
      expect(described_class.adapters.count(custom_adapter)).to eq(1)
    end

    it "clears the memoized current selection" do
      described_class.current # memoize
      described_class.register(custom_adapter)
      # Re-reading current re-runs selection; the custom adapter is inactive
      # so the next active one wins (or nil if neither built-in is active).
      ENV.delete("TEST_ENV_NUMBER")
      expect(described_class.current).to be_nil
    end
  end

  describe ".current" do
    it "is nil when no adapter is active" do
      ENV.delete("TEST_ENV_NUMBER")
      ENV.delete("PARALLEL_TEST_GROUPS")
      expect(described_class.current).to be_nil
    end

    it "returns ParallelTestsAdapter when parallel_tests gem is loaded and native env is set" do
      stub_const("ParallelTests", Class.new)
      ENV["TEST_ENV_NUMBER"] = "1"
      ENV["PARALLEL_PID_FILE"] = "tmp/parallel_tests.pid"
      expect(described_class.current).to eq(SimpleCov::ParallelAdapters::ParallelTestsAdapter)
    end

    it "returns GenericAdapter when parallel_tests gem is loaded but the pid-file contract is absent" do
      stub_const("ParallelTests", Class.new)
      ENV["TEST_ENV_NUMBER"] = "1"
      ENV["PARALLEL_TEST_GROUPS"] = "2"
      ENV.delete("PARALLEL_PID_FILE")

      expect(described_class.current).to eq(SimpleCov::ParallelAdapters::GenericAdapter)
    end

    it "returns GenericAdapter when TEST_ENV_NUMBER is set but parallel_tests isn't loaded" do
      hide_const("ParallelTests") if defined?(ParallelTests)
      ENV["TEST_ENV_NUMBER"] = "1"
      # Force ParallelTestsAdapter to skip its auto-load attempt.
      allow(SimpleCov::ParallelAdapters::ParallelTestsAdapter).to receive(:ensure_loaded)
      expect(described_class.current).to eq(SimpleCov::ParallelAdapters::GenericAdapter)
    end

    it "memoizes — subsequent calls return the same adapter without re-checking active?" do
      ENV["TEST_ENV_NUMBER"] = "1"
      allow(SimpleCov::ParallelAdapters::ParallelTestsAdapter).to receive(:ensure_loaded)
      first = described_class.current
      ENV.delete("TEST_ENV_NUMBER") # changing env after memoization is intentionally ignored
      expect(described_class.current).to equal(first)
    end
  end

  describe SimpleCov::ParallelAdapters::Base do
    it "active? defaults to false (a base adapter is never selected)" do
      expect(described_class.active?).to be false
    end

    it "first_worker? defaults to true (single-process semantics)" do
      expect(described_class.first_worker?).to be true
    end

    it "wait_for_siblings is a no-op" do
      expect { described_class.wait_for_siblings }.not_to raise_error
      expect(described_class.wait_for_siblings).to be_nil
    end

    it "expected_worker_count defaults to 1 (single-process)" do
      expect(described_class.expected_worker_count).to eq(1)
    end
  end

  describe SimpleCov::ParallelAdapters::GenericAdapter do
    around do |example|
      prev = ENV.fetch("TEST_ENV_NUMBER", nil)
      prev_groups = ENV.fetch("PARALLEL_TEST_GROUPS", nil)
      example.run
    ensure
      ENV["TEST_ENV_NUMBER"] = prev
      ENV["PARALLEL_TEST_GROUPS"] = prev_groups
    end

    describe ".active?" do
      it "is true when TEST_ENV_NUMBER is set" do
        ENV["TEST_ENV_NUMBER"] = "1"
        expect(described_class.active?).to be true
      end

      it "is false when TEST_ENV_NUMBER is not set" do
        ENV.delete("TEST_ENV_NUMBER")
        expect(described_class.active?).to be false
      end

      it "is true even for empty string (parallel_tests's convention for the first worker)" do
        ENV["TEST_ENV_NUMBER"] = ""
        expect(described_class.active?).to be true
      end

      it "is false when SimpleCov.parallel_tests is false" do
        previous = SimpleCov.parallel_tests
        SimpleCov.parallel_tests false
        ENV["TEST_ENV_NUMBER"] = "1"

        expect(described_class.active?).to be false
      ensure
        SimpleCov.parallel_tests previous
      end
    end

    describe ".first_worker?" do
      it 'returns true for TEST_ENV_NUMBER == "" (parallel_tests/parallel_rspec first-worker convention)' do
        ENV["TEST_ENV_NUMBER"] = ""
        expect(described_class.first_worker?).to be true
      end

      it 'returns true for TEST_ENV_NUMBER == "1" (1-based runners)' do
        ENV["TEST_ENV_NUMBER"] = "1"
        expect(described_class.first_worker?).to be true
      end

      it "returns false for any other TEST_ENV_NUMBER value" do
        ENV["TEST_ENV_NUMBER"] = "2"
        expect(described_class.first_worker?).to be false
      end
    end

    describe ".expected_worker_count" do
      it "reads PARALLEL_TEST_GROUPS" do
        ENV["PARALLEL_TEST_GROUPS"] = "4"
        expect(described_class.expected_worker_count).to eq(4)
      end

      it "defaults to 1 when PARALLEL_TEST_GROUPS is unset" do
        ENV.delete("PARALLEL_TEST_GROUPS")
        expect(described_class.expected_worker_count).to eq(1)
      end
    end

    it "wait_for_siblings is a no-op (no native runner API)" do
      expect(described_class.wait_for_siblings).to be_nil
    end
  end

  describe SimpleCov::ParallelAdapters::ParallelTestsAdapter do
    around do |example|
      prev = ENV.fetch("TEST_ENV_NUMBER", nil)
      prev_groups = ENV.fetch("PARALLEL_TEST_GROUPS", nil)
      prev_pid_file = ENV.fetch("PARALLEL_PID_FILE", nil)
      example.run
    ensure
      ENV["TEST_ENV_NUMBER"] = prev
      ENV["PARALLEL_TEST_GROUPS"] = prev_groups
      ENV["PARALLEL_PID_FILE"] = prev_pid_file
    end

    describe ".active?" do
      it "is true when ParallelTests is loaded and the native env contract is set" do
        stub_const("ParallelTests", Class.new)
        ENV["TEST_ENV_NUMBER"] = "1"
        ENV["PARALLEL_PID_FILE"] = "tmp/parallel_tests.pid"
        allow(described_class).to receive(:ensure_loaded)
        expect(described_class.active?).to be true
      end

      it "is false when ParallelTests isn't loaded" do
        hide_const("ParallelTests") if defined?(ParallelTests)
        ENV["TEST_ENV_NUMBER"] = "1"
        allow(described_class).to receive(:ensure_loaded)
        expect(described_class.active?).to be false
      end

      it "is false when PARALLEL_PID_FILE is unset" do
        stub_const("ParallelTests", Class.new)
        ENV["TEST_ENV_NUMBER"] = "1"
        ENV.delete("PARALLEL_PID_FILE")
        allow(described_class).to receive(:ensure_loaded)
        expect(described_class.active?).to be false
      end

      it "is false when TEST_ENV_NUMBER is unset" do
        stub_const("ParallelTests", Class.new)
        ENV.delete("TEST_ENV_NUMBER")
        ENV["PARALLEL_PID_FILE"] = "tmp/parallel_tests.pid"
        allow(described_class).to receive(:ensure_loaded)
        expect(described_class.active?).to be false
      end

      it "is false when SimpleCov.parallel_tests is false even if ParallelTests is already loaded" do
        stub_const("ParallelTests", Class.new)
        ENV["TEST_ENV_NUMBER"] = "1"
        ENV["PARALLEL_PID_FILE"] = "tmp/parallel_tests.pid"
        previous = SimpleCov.parallel_tests
        SimpleCov.parallel_tests false

        expect(described_class.active?).to be false
      ensure
        SimpleCov.parallel_tests previous
      end
    end

    describe ".first_worker?" do
      it "delegates to ParallelTests.first_process?" do
        truthy_fake = Class.new { def self.first_process? = true }
        stub_const("ParallelTests", truthy_fake)
        expect(described_class.first_worker?).to be true

        falsy_fake = Class.new { def self.first_process? = false }
        stub_const("ParallelTests", falsy_fake)
        expect(described_class.first_worker?).to be false
      end
    end

    describe ".wait_for_siblings" do
      it "delegates to ParallelTests.wait_for_other_processes_to_finish" do
        fake = Class.new { def self.wait_for_other_processes_to_finish = :sentinel }
        stub_const("ParallelTests", fake)
        expect(described_class.wait_for_siblings).to eq(:sentinel)
      end
    end

    describe ".expected_worker_count" do
      it "reads PARALLEL_TEST_GROUPS" do
        ENV["PARALLEL_TEST_GROUPS"] = "3"
        expect(described_class.expected_worker_count).to eq(3)
      end

      it "defaults to 1 when PARALLEL_TEST_GROUPS is unset" do
        ENV.delete("PARALLEL_TEST_GROUPS")
        expect(described_class.expected_worker_count).to eq(1)
      end
    end

    describe ".ensure_loaded" do
      it "is a no-op when ParallelTests is already loaded" do
        stub_const("ParallelTests", Class.new)
        expect { described_class.ensure_loaded }.not_to raise_error
      end

      it "is a no-op when SimpleCov.parallel_tests is false" do
        hide_const("ParallelTests") if defined?(ParallelTests)
        previous = SimpleCov.parallel_tests
        SimpleCov.parallel_tests false
        expect { described_class.ensure_loaded }.not_to raise_error
      ensure
        SimpleCov.parallel_tests previous
      end

      it "silently swallows LoadError when the gem isn't installed" do
        hide_const("ParallelTests") if defined?(ParallelTests)
        ENV["TEST_ENV_NUMBER"] = "1"
        ENV["PARALLEL_TEST_GROUPS"] = "2"
        previous = SimpleCov.parallel_tests
        SimpleCov.parallel_tests nil # force the env-suggests path
        allow(described_class).to receive(:require).with("parallel_tests").and_raise(LoadError)
        expect { described_class.ensure_loaded }.not_to raise_error
      ensure
        SimpleCov.parallel_tests previous
      end
    end
  end
end
