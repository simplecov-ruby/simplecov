# frozen_string_literal: true

require "helper"
require "tmpdir"

RSpec.describe SimpleCov::Baseline do
  describe ".read" do
    it "returns nil when the file does not exist" do
      Dir.mktmpdir do |dir|
        expect(described_class.read(File.join(dir, ".simplecov_baseline.yml"))).to be_nil
      end
    end

    it "parses the canonical per-criterion form" do
      baseline = read_baseline(<<~YAML)
        lib/foo.rb:
          lines:
            percent: 41.2
            missed: 137
          branches:
            percent: 25.0
            missed: 48
      YAML

      expect(baseline.floor_for("lib/foo.rb", :line)).to have_attributes(percent: 41.2, missed: 137)
      expect(baseline.floor_for("lib/foo.rb", :branch)).to have_attributes(percent: 25.0, missed: 48)
    end

    # The issue's own example is the scalar form. A hand-written
    # `path: 41.2` reads as a line-percent floor with no missed-count
    # dampener rather than being rejected.
    it "accepts a bare number as a line-percent floor" do
      baseline = read_baseline("lib/foo.rb: 41.2\n")

      expect(baseline.floor_for("lib/foo.rb", :line)).to have_attributes(percent: 41.2, missed: nil)
    end

    it "accepts a criterion entry that is a bare percent" do
      baseline = read_baseline(<<~YAML)
        lib/foo.rb:
          branches: 25.0
      YAML

      expect(baseline.floor_for("lib/foo.rb", :branch)).to have_attributes(percent: 25.0, missed: nil)
      expect(baseline.floor_for("lib/foo.rb", :line)).to be_nil
    end

    it "raises a configuration error for invalid YAML" do
      expect { read_baseline("{") }
        .to raise_error(SimpleCov::ConfigurationError, /baseline/)
    end

    it "raises a configuration error for an unknown criterion key" do
      expect { read_baseline("lib/foo.rb:\n  bogus: 41.2\n") }
        .to raise_error(SimpleCov::ConfigurationError, /bogus/)
    end

    it "raises a configuration error for a non-numeric floor" do
      expect { read_baseline("lib/foo.rb: high\n") }
        .to raise_error(SimpleCov::ConfigurationError, %r{lib/foo\.rb})
    end

    it "raises a configuration error for a criterion floor that is neither number nor Hash" do
      expect { read_baseline("lib/foo.rb:\n  lines: high\n") }
        .to raise_error(SimpleCov::ConfigurationError, /percent/)
    end

    it "raises a configuration error when the document is not a Hash at all" do
      expect { read_baseline("- lib/foo.rb\n") }
        .to raise_error(SimpleCov::ConfigurationError, /must map file paths/)
    end

    it "raises a configuration error for a floor hash without a percent" do
      expect { read_baseline("lib/foo.rb:\n  lines:\n    missed: 3\n") }
        .to raise_error(SimpleCov::ConfigurationError, /percent/)
    end

    it "raises a configuration error for a non-integer missed count" do
      expect { read_baseline("lib/foo.rb:\n  lines:\n    percent: 41.2\n    missed: many\n") }
        .to raise_error(SimpleCov::ConfigurationError, /missed count/)
    end
  end

  describe "#covers?" do
    it "answers per file and criterion" do
      baseline = read_baseline(<<~YAML)
        lib/foo.rb:
          lines:
            percent: 41.2
            missed: 137
      YAML

      expect(baseline.covers?("lib/foo.rb", :line)).to be true
      expect(baseline.covers?("lib/foo.rb", :branch)).to be false
      expect(baseline.covers?("lib/bar.rb", :line)).to be false
    end
  end

  describe "#ratchet" do
    let(:existing) do
      read_baseline(<<~YAML)
        lib/improved.rb:
          lines:
            percent: 40.0
            missed: 10
        lib/regressed.rb:
          lines:
            percent: 90.0
            missed: 2
        lib/deleted.rb:
          lines:
            percent: 50.0
            missed: 5
      YAML
    end

    let(:current) do
      {
        "lib/improved.rb" => {line: {percent: 75.0, missed: 4}},
        "lib/regressed.rb" => {line: {percent: 80.0, missed: 6}},
        "lib/brand_new.rb" => {line: {percent: 10.0, missed: 90}}
      }
    end

    let(:outcome) { existing.ratchet(current) }

    it "raises the floor of a file that improved" do
      expect(outcome.baseline.floor_for("lib/improved.rb", :line)).to have_attributes(percent: 75.0, missed: 4)
      expect(outcome.tightened).to eq(["lib/improved.rb"])
    end

    it "never lowers the floor of a file that regressed" do
      expect(outcome.baseline.floor_for("lib/regressed.rb", :line)).to have_attributes(percent: 90.0, missed: 2)
      expect(outcome.regressed).to eq(["lib/regressed.rb"])
    end

    # The regressed list mirrors the exit check's verdict: a percent
    # drift the missed-count dampener tolerates is not reported as
    # "below its floor", because the check would pass the file.
    it "counts a percent drop with no new misses as unchanged, matching the check" do
      baseline = read_baseline(<<~YAML)
        lib/drifted.rb:
          lines:
            percent: 90.0
            missed: 2
      YAML
      outcome = baseline.ratchet("lib/drifted.rb" => {line: {percent: 85.0, missed: 2}})

      expect(outcome.unchanged).to eq(["lib/drifted.rb"])
      expect(outcome.regressed).to be_empty
    end

    it "prunes entries for files the report no longer carries" do
      expect(outcome.baseline.entry_for("lib/deleted.rb")).to be_nil
      expect(outcome.pruned).to eq(["lib/deleted.rb"])
    end

    # New files are held to the real standard (the global thresholds),
    # not grandfathered in at whatever they launched at.
    it "does not add entries for files the baseline never covered" do
      expect(outcome.baseline.entry_for("lib/brand_new.rb")).to be_nil
    end

    it "tightens percent and missed independently, keeping the best of each" do
      baseline = read_baseline(<<~YAML)
        lib/shrunk.rb:
          lines:
            percent: 90.0
            missed: 10
      YAML
      # The file shrank: percent dropped with fewer uncovered lines.
      outcome = baseline.ratchet("lib/shrunk.rb" => {line: {percent: 85.0, missed: 3}})

      expect(outcome.baseline.floor_for("lib/shrunk.rb", :line)).to have_attributes(percent: 90.0, missed: 3)
    end

    it "gains a missed-count dampener for a hand-written percent-only floor" do
      baseline = read_baseline("lib/foo.rb: 41.2\n")
      outcome = baseline.ratchet("lib/foo.rb" => {line: {percent: 41.2, missed: 137}})

      expect(outcome.baseline.floor_for("lib/foo.rb", :line)).to have_attributes(percent: 41.2, missed: 137)
    end

    # Enabling branch coverage later must drag the legacy files' branch
    # state into the baseline, or their branch coverage would face the
    # full per-file minimum despite being grandfathered on lines.
    it "adds newly measured criteria to existing entries" do
      baseline = read_baseline("lib/foo.rb: 41.2\n")
      outcome = baseline.ratchet(
        "lib/foo.rb" => {line: {percent: 41.2, missed: 137}, branch: {percent: 25.0, missed: 48}}
      )

      expect(outcome.baseline.floor_for("lib/foo.rb", :branch)).to have_attributes(percent: 25.0, missed: 48)
    end

    it "keeps a criterion the current run did not measure" do
      baseline = read_baseline(<<~YAML)
        lib/foo.rb:
          lines:
            percent: 41.2
            missed: 137
          branches:
            percent: 25.0
            missed: 48
      YAML
      outcome = baseline.ratchet("lib/foo.rb" => {line: {percent: 41.2, missed: 137}})

      expect(outcome.baseline.floor_for("lib/foo.rb", :branch)).to have_attributes(percent: 25.0, missed: 48)
      expect(outcome.unchanged).to eq(["lib/foo.rb"])
    end
  end

  describe ".generate" do
    it "creates an entry for every reported file" do
      baseline = described_class.generate(
        "lib/foo.rb" => {line: {percent: 41.2, missed: 137}},
        "lib/bar.rb" => {line: {percent: 100.0, missed: 0}}
      )

      expect(baseline.floor_for("lib/foo.rb", :line)).to have_attributes(percent: 41.2, missed: 137)
      expect(baseline.floor_for("lib/bar.rb", :line)).to have_attributes(percent: 100.0, missed: 0)
    end
  end

  describe "#to_yaml" do
    it "serializes entries sorted by path, with a self-describing header" do
      baseline = described_class.generate(
        "lib/zebra.rb" => {line: {percent: 50.0, missed: 5}},
        "lib/aardvark.rb" => {line: {percent: 41.2, missed: 137}, branch: {percent: 25.0, missed: 48}}
      )

      yaml = baseline.to_yaml
      expect(yaml).to start_with("# Per-file coverage floors.")
      expect(yaml.index("lib/aardvark.rb")).to be < yaml.index("lib/zebra.rb")
      expect(yaml).to include(<<~YAML)
        lib/aardvark.rb:
          lines:
            percent: 41.2
            missed: 137
          branches:
            percent: 25.0
            missed: 48
      YAML
    end

    it "round-trips through read" do
      baseline = described_class.generate("lib/foo.rb" => {line: {percent: 41.2, missed: 137}})
      round_tripped = read_baseline(baseline.to_yaml)

      expect(round_tripped.floor_for("lib/foo.rb", :line)).to have_attributes(percent: 41.2, missed: 137)
    end

    it "omits the missed key for a percent-only floor" do
      baseline = read_baseline("lib/foo.rb: 41.2\n")

      expect(baseline.to_yaml).to include("percent: 41.2\n")
      expect(baseline.to_yaml).not_to include("missed")
    end
  end

  def read_baseline(yaml)
    Dir.mktmpdir do |dir|
      path = File.join(dir, ".simplecov_baseline.yml")
      File.write(path, yaml)
      return SimpleCov::Baseline.read(path)
    end
  end
end
