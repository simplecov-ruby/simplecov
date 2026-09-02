# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::TestTracker::Accessors do
  around do |example|
    example.run
  ensure
    SimpleCov.remove_instance_variable(:@test_tracker) if SimpleCov.instance_variable_defined?(:@test_tracker)
    SimpleCov.track_tests(false)
  end

  describe "#track_test" do
    it "has no tracker to delegate to" do
      expect(SimpleCov.test_tracker).to be_nil
    end

    it "just runs the block when no tracker is live" do
      expect(SimpleCov.track_test("spec/a_spec.rb:1") { :ran }).to eq(:ran)
    end

    context "with a live tracker" do
      let(:live_tracker) { instance_double(SimpleCov::TestTracker) }

      before do
        allow(live_tracker).to receive(:track).with("spec/a_spec.rb:1").and_yield
        SimpleCov.instance_variable_set(:@test_tracker, live_tracker)
      end

      it "answers the block's value" do
        expect(SimpleCov.track_test("spec/a_spec.rb:1") { :ran }).to eq(:ran)
      end

      it "delegates to it" do
        SimpleCov.track_test("spec/a_spec.rb:1") { :ran }

        expect(live_tracker).to have_received(:track).with("spec/a_spec.rb:1")
      end
    end
  end

  describe "#start_test_tracking" do
    before { allow(SimpleCov::TestTracker).to receive(:install_framework_hooks) }

    it "builds no tracker while track_tests is off" do
      SimpleCov.start_test_tracking

      expect(SimpleCov.test_tracker).to be_nil
    end

    it "installs no framework hooks while track_tests is off" do
      SimpleCov.start_test_tracking

      expect(SimpleCov::TestTracker).not_to have_received(:install_framework_hooks)
    end

    context "when track_tests is on" do
      before do
        SimpleCov.track_tests

        SimpleCov.start_test_tracking
      end

      it "builds the tracker" do
        expect(SimpleCov.test_tracker).to be_a(SimpleCov::TestTracker)
      end

      it "installs the framework hooks" do
        expect(SimpleCov::TestTracker).to have_received(:install_framework_hooks)
      end
    end

    it "refuses to start tracking a run that cannot produce deltas" do
      SimpleCov.track_tests
      allow(SimpleCov).to receive(:coverage_criterion_enabled?).with(:line).and_return(false)

      expect { SimpleCov.start_test_tracking }.to raise_error(SimpleCov::ConfigurationError, /track_tests/)
    end

    it "builds the tracker at the configured granularity" do
      SimpleCov.track_tests(granularity: :file)

      SimpleCov.start_test_tracking

      expect(SimpleCov.test_tracker.instance_variable_get(:@granularity)).to eq(:file)
    end

    context "when tracking restarts" do
      before do
        SimpleCov.track_tests
        SimpleCov.start_test_tracking
      end

      it "keeps the tracker, and its recordings, across the restart" do
        first = SimpleCov.test_tracker

        SimpleCov.start_test_tracking

        expect(SimpleCov.test_tracker).to be(first)
      end

      it "wires the framework hooks only once" do
        SimpleCov.start_test_tracking

        expect(SimpleCov::TestTracker).to have_received(:install_framework_hooks).once
      end
    end
  end
end
