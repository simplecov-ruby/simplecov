# frozen_string_literal: true

require "yaml"

module SimpleCov
  # The checked-in per-file coverage floor behind `simplecov ratchet` (#1268):
  # `.rubocop_todo.yml` applied to coverage. Each entry records, per criterion,
  # the percent a file has already reached and the number of misses it had when
  # that percent was recorded.
  #
  # A floor carries both numbers because each covers for the other's blind
  # spot. The percent is the policy, but a percent moves when a file is edited
  # without any coverage change at all, so the missed count acts as the
  # dampener. A violation therefore requires both a lower percent and more
  # misses, which is the honest reading of "this file got worse".
  class Baseline
    DEFAULT_FILENAME = ".simplecov_baseline.yml"

    HEADER = <<~HEADER
      # Per-file coverage floors. A file that drops below its floor fails the run,
      # and files with no entry fall through to the global per-file minimum.
      # Regenerate with `simplecov ratchet`. Floors only ever tighten.
    HEADER
    private_constant :HEADER

    # The YAML file speaks the report's vocabulary; internally floors are keyed
    # by criterion the way the threshold configuration is.
    CRITERIA = {"lines" => :line, "branches" => :branch, "methods" => :method}.freeze
    private_constant :CRITERIA

    # `missed` is nil for a hand-written percent-only entry, meaning the
    # dampener is absent and the percent alone decides.
    Floor = Data.define(:percent, :missed)

    # The tightened baseline plus the path lists the CLI summarizes (each path
    # appears in exactly one).
    Outcome = Data.define(:baseline, :tightened, :pruned, :regressed, :unchanged)

    # A file that exists but cannot be read as a baseline raises
    # ConfigurationError: a malformed policy must fail loudly rather than
    # silently un-enforce every floor it carried.
    def self.read_if_exists(path)
      return nil unless File.exist?(path)

      new(Parser.call(YAML.safe_load_file(path), path))
    rescue Psych::Exception => e
      # Interpolating the exception renders the message Psych objected with.
      raise ConfigurationError, "baseline file #{path} is not valid YAML: #{e}"
    end

    # `current` is a `{project_filename => {criterion => {percent:, missed:}}}`
    # Hash of the measured state. Everything the report carries gets a floor at
    # its current coverage.
    def self.read(path)
      Deprecation.warn("`SimpleCov::Baseline.read` is deprecated. Replace with `read_if_exists`.")
      read_if_exists(path)
    end

    def self.generate(current)
      new(current.transform_values do |criteria|
        criteria.transform_values { |floor| Floor.new(percent: floor.fetch(:percent), missed: floor.fetch(:missed)) }
      end)
    end

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

    # Which is also what exempts the pair from the per-file thresholds.
    def covers?(project_filename, criterion)
      !floor_for(project_filename, criterion).nil?
    end

    # Floors only move in the tightening direction, each axis independently:
    # the percent keeps its best, the missed count its lowest. Entries for
    # files `current` does not carry are pruned; files `current` carries
    # without an entry stay uncovered, so new code answers to the global
    # standard rather than to a floor cut at whatever it launched with. A
    # criterion the current run did not measure keeps its floor, and a newly
    # measured criterion joins the entry, so a later `enable_coverage :branch`
    # grandfathers the legacy files' branch state.
    def ratchet(current)
      buckets = {tightened: [], pruned: [], regressed: [], unchanged: []} #: Hash[Symbol, Array[String]]
      ratcheted = entries.filter_map do |file, entry|
        step = ratchet_entry(entry, current[file])
        buckets.fetch(step.fetch(:bucket)) << file
        merged = step[:entry]
        [file, merged] if merged
      end.to_h

      Outcome.new(baseline: Baseline.new(ratcheted), tightened: buckets.fetch(:tightened),
        pruned: buckets.fetch(:pruned), regressed: buckets.fetch(:regressed),
        unchanged: buckets.fetch(:unchanged))
    end

    # Sorted by path so a ratchet rewrite diffs as the set of floors that
    # actually moved.
    def to_yaml
      document = entries.sort.to_h do |file, entry|
        [file, entry.to_h { |criterion, floor| [CRITERIA.key(criterion), dump_floor(floor)] }]
      end
      HEADER + YAML.dump(document).delete_prefix("---\n")
    end

    private

    # A nil current prunes the entry, which carries no replacement and so
    # answers with the bucket alone. Otherwise every measured criterion
    # tightens, keeping the ones this run did not measure.
    def ratchet_entry(entry, current_entry)
      return {bucket: :pruned} unless current_entry

      merged = (entry.keys | current_entry.keys).to_h do |criterion|
        [criterion, tighten(entry[criterion], current_entry[criterion])]
      end
      {bucket: bucket_for(entry, merged, current_entry), entry: merged}
    end

    # The regressed bucket mirrors the violation rule exactly, so "below its
    # floor" in the ratchet summary always means the exit check fails the file,
    # never a percent drift the dampener tolerates.
    def bucket_for(entry, merged, current_entry)
      # Exact equality rather than numeric: tightening keeps the entry's own
      # floor on a tie, so an entry that did not move is the very values it
      # came in with.
      return :tightened unless merged.eql?(entry)

      regressed = entry.any? do |criterion, floor|
        current = current_entry[criterion]
        current && current.fetch(:percent) < floor.percent &&
          (floor.missed.nil? || current.fetch(:missed) > floor.missed)
      end
      regressed ? :regressed : :unchanged
    end

    # Either side may be absent: a floor with no current measurement stays, a
    # measurement with no floor becomes one.
    def tighten(floor, current)
      # The keys union in ratchet_entry guarantees at least one side is present,
      # which the cast restates for the type checker.
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
