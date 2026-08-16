# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::TestContexts do
  after { SimpleCov.clear_test_context_recorder! }

  describe ".activate!" do
    before { allow(SimpleCov::TestContexts::Hooks).to receive(:install!) }

    it "installs a recorder and the framework hooks" do
      allow(SimpleCov).to receive(:forked_subprocess?).and_return(false)

      described_class.activate!

      expect(SimpleCov.test_context_recorder).to be_a(SimpleCov::TestContexts::Recorder)
      expect(SimpleCov::TestContexts::Hooks).to have_received(:install!)
    end

    it "does nothing in a forked child" do
      allow(SimpleCov).to receive(:forked_subprocess?).and_return(true)

      described_class.activate!

      expect(SimpleCov.test_context_recorder).to be_nil
      expect(SimpleCov::TestContexts::Hooks).not_to have_received(:install!)
    end
  end

  describe "activation through SimpleCov.start_coverage_measurement" do
    it "activates the recording when test_contexts :per_test is set" do
      require "coverage"
      SimpleCov.test_contexts :per_test
      allow(described_class).to receive(:activate!)
      # Keep the example hermetic outside the dogfood bootstrap too: a
      # session that is already running must not be restarted, and one
      # that is not must not leak a fresh global session.
      allow(Coverage).to receive(:running?).and_return(true)

      SimpleCov.send(:start_coverage_measurement)

      expect(described_class).to have_received(:activate!)
    ensure
      SimpleCov.test_contexts nil
    end
  end

  describe "SimpleCov.install_test_context_recorder!" do
    it "keeps the live recorder when SimpleCov.start runs again" do
      SimpleCov.install_test_context_recorder!
      first = SimpleCov.test_context_recorder

      SimpleCov.install_test_context_recorder!

      expect(SimpleCov.test_context_recorder).to equal(first)
    end
  end

  describe "SimpleCov.test_context_payload" do
    it "is nil when recording never started" do
      expect(SimpleCov.test_context_payload).to be_nil
    end

    it "returns the recorder's map once a framework hook is attached" do
      SimpleCov.install_test_context_recorder!
      allow(SimpleCov::TestContexts::Hooks).to receive(:installed_any?).and_return(true)

      expect(SimpleCov.test_context_payload).to be_a(SimpleCov::TestContexts::Map)
    end

    it "warns and returns nil when no framework hook was ever attached" do
      SimpleCov.install_test_context_recorder!
      allow(SimpleCov::TestContexts::Hooks).to receive(:installed_any?).and_return(false)

      payload = :unset
      stderr = capture_stderr { payload = SimpleCov.test_context_payload }

      expect(payload).to be_nil
      expect(stderr).to include("neither the RSpec nor the Minitest hook")
    end

    it "stays quiet about a missing hook when print_errors is off" do
      SimpleCov.install_test_context_recorder!
      allow(SimpleCov::TestContexts::Hooks).to receive(:installed_any?).and_return(false)
      allow(SimpleCov).to receive(:print_errors).and_return(false)

      stderr = capture_stderr { expect(SimpleCov.test_context_payload).to be_nil }

      expect(stderr).to be_empty
    end
  end
end
