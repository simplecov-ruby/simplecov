# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::Color do
  describe ".for_percent" do
    it "returns :green for percentages at or above the green threshold" do
      expect(described_class.for_percent(90.0)).to eq(:green)
      expect(described_class.for_percent(99.99)).to eq(:green)
      expect(described_class.for_percent(100.0)).to eq(:green)
    end

    it "returns :yellow between the yellow and green thresholds" do
      expect(described_class.for_percent(75.0)).to eq(:yellow)
      expect(described_class.for_percent(80.0)).to eq(:yellow)
      expect(described_class.for_percent(89.99)).to eq(:yellow)
    end

    it "returns :red below the yellow threshold" do
      expect(described_class.for_percent(0.0)).to eq(:red)
      expect(described_class.for_percent(74.99)).to eq(:red)
    end
  end

  describe ".enabled?" do
    around do |example|
      previous_no = ENV.fetch("NO_COLOR", nil)
      previous_force = ENV.fetch("FORCE_COLOR", nil)
      ENV.delete("NO_COLOR")
      ENV.delete("FORCE_COLOR")
      example.run
    ensure
      # Restore both env vars regardless of whether they were originally set.
      # Leaking ENV["FORCE_COLOR"]="1" into subsequent tests in the full
      # suite would flip SimpleCov::Color.enabled? on for unrelated specs.
      previous_no ? ENV["NO_COLOR"] = previous_no : ENV.delete("NO_COLOR")
      previous_force ? ENV["FORCE_COLOR"] = previous_force : ENV.delete("FORCE_COLOR")
    end

    # SimpleCov.color is module-global; the assigned value would leak
    # between examples (and into the rest of the suite) without this.
    before { SimpleCov.color :auto }
    after  { SimpleCov.color :auto }

    it "returns false when NO_COLOR is set (regardless of TTY)" do
      ENV["NO_COLOR"] = "1"
      allow($stderr).to receive(:tty?).and_return(true)
      expect(described_class).not_to be_enabled
    end

    it "ignores an empty NO_COLOR (per the no-color.org convention)" do
      ENV["NO_COLOR"] = ""
      allow($stderr).to receive(:tty?).and_return(true)
      expect(described_class).to be_enabled
    end

    it "returns true when FORCE_COLOR is set, even without a TTY" do
      ENV["FORCE_COLOR"] = "1"
      allow($stderr).to receive(:tty?).and_return(false)
      expect(described_class).to be_enabled
    end

    it "NO_COLOR wins over FORCE_COLOR if both are set" do
      ENV["NO_COLOR"] = "1"
      ENV["FORCE_COLOR"] = "1"
      expect(described_class).not_to be_enabled
    end

    it "falls back to stderr.tty? when neither env var is set" do
      allow($stderr).to receive(:tty?).and_return(true)
      expect(described_class).to be_enabled

      allow($stderr).to receive(:tty?).and_return(false)
      expect(described_class).not_to be_enabled
    end

    it "checks the given stream when one is passed" do
      stdout_tty = StringIO.new
      allow(stdout_tty).to receive(:tty?).and_return(true)
      expect(described_class.enabled?(stdout_tty)).to be true

      stdout_not_tty = StringIO.new
      allow(stdout_not_tty).to receive(:tty?).and_return(false)
      expect(described_class.enabled?(stdout_not_tty)).to be false
    end

    context "when SimpleCov.color is set explicitly" do
      it "returns true when set to true, overriding a non-TTY stream" do
        SimpleCov.color true
        allow($stderr).to receive(:tty?).and_return(false)
        expect(described_class).to be_enabled
      end

      it "returns false when set to false, overriding a TTY stream" do
        SimpleCov.color false
        allow($stderr).to receive(:tty?).and_return(true)
        expect(described_class).not_to be_enabled
      end

      it "wins over NO_COLOR (explicit programmatic intent overrides env)" do
        SimpleCov.color true
        ENV["NO_COLOR"] = "1"
        expect(described_class).to be_enabled
      end

      it "wins over FORCE_COLOR when set to false" do
        SimpleCov.color false
        ENV["FORCE_COLOR"] = "1"
        expect(described_class).not_to be_enabled
      end

      it "falls through to env vars and TTY when set to :auto" do
        SimpleCov.color :auto
        ENV["FORCE_COLOR"] = "1"
        allow($stderr).to receive(:tty?).and_return(false)
        expect(described_class).to be_enabled
      end
    end
  end

  describe ".colorize" do
    it "wraps text in the ANSI sequence when color is enabled" do
      allow(described_class).to receive(:enabled?).and_return(true)
      expect(described_class.colorize("hi", :red)).to eq("\e[31mhi\e[0m")
    end

    it "returns the bare text when color is disabled" do
      allow(described_class).to receive(:enabled?).and_return(false)
      expect(described_class.colorize("hi", :red)).to eq("hi")
    end

    it "raises for an unknown color (so a typo doesn't silently fall through)" do
      allow(described_class).to receive(:enabled?).and_return(true)
      expect { described_class.colorize("hi", :magenta) }.to raise_error(KeyError)
    end

    it "honors an explicit enabled: false even when auto-detect would enable" do
      allow(described_class).to receive(:enabled?).and_return(true)
      expect(described_class.colorize("hi", :red, enabled: false)).to eq("hi")
    end

    it "honors an explicit enabled: true even when auto-detect would disable" do
      allow(described_class).to receive(:enabled?).and_return(false)
      expect(described_class.colorize("hi", :red, enabled: true)).to eq("\e[31mhi\e[0m")
    end
  end

  describe ".colorize_percent" do
    before { allow(described_class).to receive(:enabled?).and_return(true) }

    it "renders as NN.NN% in green for >= 90" do
      expect(described_class.colorize_percent(95.5)).to eq("\e[32m95.50%\e[0m")
    end

    it "renders as NN.NN% in yellow for >= 75 and < 90" do
      expect(described_class.colorize_percent(80.0)).to eq("\e[33m80.00%\e[0m")
    end

    it "renders as NN.NN% in red below 75" do
      expect(described_class.colorize_percent(40.0)).to eq("\e[31m40.00%\e[0m")
    end

    it "honours an explicit pre-rendered text" do
      expect(described_class.colorize_percent(40.0, "  40.00%")).to eq("\e[31m  40.00%\e[0m")
    end
  end
end
