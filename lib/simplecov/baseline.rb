# frozen_string_literal: true

require "yaml"

module SimpleCov
  # The checked-in per-file coverage floor set behind `simplecov ratchet`
  # (see #1268): `.rubocop_todo.yml` applied to coverage. Each entry
  # records, per criterion, the percent a file has already reached and
  # the number of misses it had when that percent was recorded. The exit
  # check fails a file that drops below its own floor, files with no
  # entry fall through to the global per-file minimum, and `ratchet`
  # rewrites the file so floors only ever tighten.
  #
  # A floor carries both numbers because each covers for the other's
  # blind spot. The percent is the policy (it is what `minimum_coverage`
  # speaks), but a percent moves when a file is edited without any
  # coverage change at all, so the missed count acts as the dampener: a
  # file below its percent floor still passes while it carries no more
  # misses than the floor recorded. A violation therefore requires both
  # a lower percent and more misses, which is the honest reading of
  # "this file got worse".
  class Baseline
    DEFAULT_FILENAME = ".simplecov_baseline.yml"

    HEADER = <<~HEADER
      # Per-file coverage floors. A file that drops below its floor fails the run,
      # and files with no entry fall through to the global per-file minimum.
      # Regenerate with `simplecov ratchet`. Floors only ever tighten.
    HEADER
    private_constant :HEADER

    # The YAML file speaks the report's vocabulary (lines / branches /
    # methods); internally floors are keyed by criterion the way the
    # threshold configuration is.
    CRITERIA = {"lines" => :line, "branches" => :branch, "methods" => :method}.freeze
    private_constant :CRITERIA

    # One criterion's floor. `missed` is nil for a hand-written
    # percent-only entry, meaning the dampener is absent and the percent
    # alone decides.
    Floor = Data.define(:percent, :missed)

    # The result of a `ratchet` pass: the tightened baseline plus the
    # path lists the CLI summarizes (each path appears in exactly one).
    Outcome = Data.define(:baseline, :tightened, :pruned, :regressed, :unchanged)

    # Parse `path` into a Baseline, nil when the file does not exist. A
    # file that exists but cannot be read as a baseline raises
    # ConfigurationError: a malformed policy must fail loudly rather
    # than silently un-enforce every floor it carried.
    def self.read(path)
      return nil unless File.exist?(path)

      new(Parser.call(YAML.safe_load_file(path), path))
    rescue Psych::Exception => e
      raise ConfigurationError, "baseline file #{path} is not valid YAML: #{e.message}"
    end

    # Build a Baseline covering every file of `current`, a
    # `{project_filename => {criterion => {percent:, missed:}}}` Hash of
    # the measured state. This is the "first run" shape: everything the
    # report carries gets a floor at its current coverage.
    def self.generate(current)
      new(current.transform_values do |criteria|
        criteria.transform_values { |floor| Floor.new(percent: floor.fetch(:percent), missed: floor.fetch(:missed)) }
      end)
    end

    # entries: Hash[project_filename, Hash[criterion, Floor]]
    attr_reader :entries

    def initialize(entries)
      @entries = entries
    end

    def entry_for(project_filename)
      entries[project_filename]
    end

    def floor_for(project_filename, criterion)
      entries.dig(project_filename, criterion)
    end

    # Whether this baseline governs the given file and criterion, which
    # is also what exempts the pair from `minimum_per_file`.
    def covers?(project_filename, criterion)
      !floor_for(project_filename, criterion).nil?
    end

    # Tighten every entry against `current` (same shape `generate`
    # takes) and return the Outcome. Floors only move in the tightening
    # direction, each axis independently: the percent keeps its best,
    # the missed count its lowest, so the pair is the envelope of the
    # best state each axis has ever seen. Entries for files `current`
    # does not carry are pruned; files `current` carries without an
    # entry stay uncovered, so new code answers to the global standard
    # rather than to a floor cut at whatever it launched with. A
    # criterion the current run did not measure keeps its floor, and a
    # newly measured criterion joins the entry, so a later
    # `enable_coverage :branch` grandfathers the legacy files' branch
    # state the same way their line state was.
    def ratchet(current)
      buckets = {tightened: [], pruned: [], regressed: [], unchanged: []} #: Hash[Symbol, Array[String]]
      ratcheted = entries.filter_map do |file, entry|
        bucket, new_entry = ratchet_entry(entry, current[file])
        buckets.fetch(bucket) << file
        [file, new_entry] if new_entry
      end.to_h

      Outcome.new(baseline: Baseline.new(ratcheted), tightened: buckets.fetch(:tightened),
                  pruned: buckets.fetch(:pruned), regressed: buckets.fetch(:regressed),
                  unchanged: buckets.fetch(:unchanged))
    end

    # Serialize in the report's vocabulary, sorted by path so a ratchet
    # rewrite diffs as the set of floors that actually moved.
    def to_yaml
      document = entries.sort.to_h do |file, entry|
        [file, entry.to_h { |criterion, floor| [CRITERIA.key(criterion), dump_floor(floor)] }]
      end
      HEADER + YAML.dump(document).delete_prefix("---\n")
    end

  private

    # One entry's ratchet step: nil current prunes the entry, otherwise
    # every measured criterion tightens (keeping unmeasured ones), and
    # the file lands in exactly one summary bucket.
    def ratchet_entry(entry, current_entry)
      return [:pruned, nil] unless current_entry

      merged = (entry.keys | current_entry.keys).to_h do |criterion|
        [criterion, tighten(entry[criterion], current_entry[criterion])]
      end
      [bucket_for(entry, merged, current_entry), merged]
    end

    # The regressed bucket mirrors the violation rule exactly (percent
    # below the floor AND more misses than it allows), so "below its
    # floor" in the ratchet summary always means the exit check fails
    # the file, never a percent drift the dampener tolerates.
    def bucket_for(entry, merged, current_entry)
      return :tightened if merged != entry

      regressed = entry.any? do |criterion, floor|
        current = current_entry[criterion]
        current && current.fetch(:percent) < floor.percent &&
          (floor.missed.nil? || current.fetch(:missed) > floor.missed)
      end
      regressed ? :regressed : :unchanged
    end

    # The tightening rule for one criterion. Either side may be absent:
    # a floor with no current measurement stays, a measurement with no
    # floor becomes one.
    def tighten(floor, current)
      # The keys union in ratchet_entry guarantees at least one side is
      # present, which the cast restates for the type checker.
      return (_ = floor) unless current

      current_floor = Floor.new(percent: current.fetch(:percent), missed: current.fetch(:missed))
      return current_floor unless floor

      Floor.new(
        percent: [floor.percent, current_floor.percent].max,
        missed: [floor.missed, current_floor.missed].compact.min
      )
    end

    def dump_floor(floor)
      dumped = {"percent" => floor.percent} #: Hash[String, untyped]
      dumped["missed"] = floor.missed unless floor.missed.nil?
      dumped
    end
  end
end

require_relative "baseline/parser"
