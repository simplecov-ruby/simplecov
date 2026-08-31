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

    it "keeps a floor hash that carries a percent but no missed count" do
      baseline = read_baseline("lib/foo.rb:\n  lines:\n    percent: 41.2\n")

      expect(baseline.floor_for("lib/foo.rb", :line)).to have_attributes(percent: 41.2, missed: nil)
    end

    it "raises a configuration error naming the file for invalid YAML" do
      with_baseline_file("{") do |path|
        expect { described_class.read(path) }.to raise_error(
          SimpleCov::ConfigurationError,
          /\Abaseline file #{Regexp.escape(path)} is not valid YAML: \S/
        )
      end
    end

    it "raises a configuration error for an unknown criterion key" do
      expect_rejection(
        "lib/foo.rb:\n  bogus: 41.2\n",
        "baseline file %<path>s: unknown criterion \"bogus\" for lib/foo.rb " \
        "(expected lines, branches, or methods)"
      )
    end

    it "raises a configuration error for a non-numeric floor" do
      expect_rejection(
        "lib/foo.rb: high\n",
        "baseline file %<path>s: entry for lib/foo.rb must be a number or a criteria Hash"
      )
    end

    it "raises a configuration error for a criterion floor that is neither number nor Hash" do
      expect_rejection(
        "lib/foo.rb:\n  lines: high\n",
        "baseline file %<path>s: floor for lib/foo.rb needs a numeric percent"
      )
    end

    it "raises a configuration error for a criterion floor that is a sequence" do
      expect_rejection(
        "lib/foo.rb:\n  lines:\n    - 41.2\n",
        "baseline file %<path>s: floor for lib/foo.rb needs a numeric percent"
      )
    end

    it "raises a configuration error when the document is not a Hash at all" do
      expect_rejection("- lib/foo.rb\n", "baseline file %<path>s must map file paths to floors")
    end

    it "raises a configuration error for a floor hash whose percent is not a number" do
      expect_rejection(
        "lib/foo.rb:\n  lines:\n    percent: high\n",
        "baseline file %<path>s: floor for lib/foo.rb needs a numeric percent"
      )
    end

    it "raises a configuration error for a floor hash without a percent" do
      expect_rejection(
        "lib/foo.rb:\n  lines:\n    missed: 3\n",
        "baseline file %<path>s: floor for lib/foo.rb needs a numeric percent"
      )
    end

    it "raises a configuration error for a non-integer missed count" do
      expect_rejection(
        "lib/foo.rb:\n  lines:\n    percent: 41.2\n    missed: many\n",
        "baseline file %<path>s: missed count for lib/foo.rb must be an integer"
      )
    end
  end

  describe "the parser" do
    it "stringifies file and criterion keys a caller supplies as Symbols" do
      entries = SimpleCov::Baseline::Parser.call({"lib/foo.rb": {lines: 41.2}}, "somewhere.yml")

      expect(entries).to eq("lib/foo.rb" => {line: SimpleCov::Baseline::Floor.new(percent: 41.2, missed: nil)})
    end

    it "reads a Hash subclass wherever a mapping is expected" do
      mapping = Class.new(Hash)
      floor = mapping.new.merge!("percent" => 41.2, "missed" => 137)
      document = mapping.new.merge!("lib/foo.rb" => mapping.new.merge!("lines" => floor))

      entries = SimpleCov::Baseline::Parser.call(document, "somewhere.yml")

      expect(entries).to eq("lib/foo.rb" => {line: SimpleCov::Baseline::Floor.new(percent: 41.2, missed: 137)})
    end
  end

  describe "#entry_for" do
    let(:baseline) do
      read_baseline(<<~YAML)
        lib/foo.rb:
          lines:
            percent: 41.2
            missed: 137
      YAML
    end

    it "answers the floors recorded for a covered file" do
      expect(baseline.entry_for("lib/foo.rb"))
        .to eq(line: SimpleCov::Baseline::Floor.new(percent: 41.2, missed: 137))
    end

    it "answers nil for a file the baseline does not cover" do
      expect(baseline.entry_for("lib/bar.rb")).to be_nil
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
      expect(outcome.baseline.entries.keys).to eq(["lib/improved.rb", "lib/regressed.rb"])
      expect(outcome.pruned).to eq(["lib/deleted.rb"])
    end

    it "reports a file whose branch floor alone was breached" do
      baseline = read_baseline(<<~YAML)
        lib/mixed.rb:
          lines:
            percent: 90.0
            missed: 2
          branches:
            percent: 80.0
            missed: 4
      YAML
      outcome = baseline.ratchet(
        "lib/mixed.rb" => {line: {percent: 90.0, missed: 2}, branch: {percent: 70.0, missed: 9}}
      )

      expect(outcome.regressed).to eq(["lib/mixed.rb"])
      expect(outcome.unchanged).to be_empty
    end

    it "counts a file sitting exactly on its percent floor as unchanged" do
      baseline = read_baseline(<<~YAML)
        lib/level.rb:
          lines:
            percent: 90.0
            missed: 2
      YAML
      outcome = baseline.ratchet("lib/level.rb" => {line: {percent: 90.0, missed: 3}})

      expect(outcome.unchanged).to eq(["lib/level.rb"])
      expect(outcome.regressed).to be_empty
    end

    it "reports a percent drop below a floor that carries no missed count" do
      baseline = read_baseline("lib/plain.rb: 41.2\n")
      outcome = baseline.ratchet("lib/plain.rb" => {line: {percent: 30.0, missed: nil}})

      expect(outcome.regressed).to eq(["lib/plain.rb"])
      expect(outcome.baseline.floor_for("lib/plain.rb", :line)).to have_attributes(percent: 41.2, missed: nil)
    end

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
      outcome = baseline.ratchet("lib/shrunk.rb" => {line: {percent: 85.0, missed: 3}})

      expect(outcome.baseline.floor_for("lib/shrunk.rb", :line)).to have_attributes(percent: 90.0, missed: 3)
    end

    it "gains a missed-count dampener for a hand-written percent-only floor" do
      baseline = read_baseline("lib/foo.rb: 41.2\n")
      outcome = baseline.ratchet("lib/foo.rb" => {line: {percent: 41.2, missed: 137}})

      expect(outcome.baseline.floor_for("lib/foo.rb", :line)).to have_attributes(percent: 41.2, missed: 137)
    end

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
    it "writes the header and one sorted mapping, with no document separator" do
      baseline = described_class.generate(
        "lib/zebra.rb" => {line: {percent: 50.0, missed: 5}},
        "lib/aardvark.rb" => {line: {percent: 41.2, missed: 137}}
      )

      expect(baseline.to_yaml).to eq(<<~YAML)
        # Per-file coverage floors. A file that drops below its floor fails the run,
        # and files with no entry fall through to the global per-file minimum.
        # Regenerate with `simplecov ratchet`. Floors only ever tighten.
        lib/aardvark.rb:
          lines:
            percent: 41.2
            missed: 137
        lib/zebra.rb:
          lines:
            percent: 50.0
            missed: 5
      YAML
    end

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
    with_baseline_file(yaml) { |path| SimpleCov::Baseline.read(path) }
  end

  def with_baseline_file(yaml)
    Dir.mktmpdir do |dir|
      path = File.join(dir, ".simplecov_baseline.yml")
      File.write(path, yaml)
      return yield(path)
    end
  end

  def expect_rejection(yaml, message)
    with_baseline_file(yaml) do |path|
      expect { SimpleCov::Baseline.read(path) }
        .to raise_error(SimpleCov::ConfigurationError, format(message, path: path))
    end
  end
end
