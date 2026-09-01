# frozen_string_literal: true

require_relative "../atomic_file"
require_relative "command_helpers"
require_relative "coverage_file"
require_relative "ratchet/output"

module SimpleCov
  module CLI
    # `simplecov ratchet`: rewrite the checked-in per-file coverage baseline
    # (#1268) from the current report. Floors only ever tighten, entries for
    # files the report no longer carries are pruned, and files without an entry
    # are never given one, so new code stays answerable to the global thresholds
    # rather than to a floor cut at whatever it launched with. `--init`
    # regenerates the whole file from the current state.
    #
    # The baseline path follows the project's `.simplecov` `baseline_file`
    # setting when one is present, the same way the read-only commands follow
    # `coverage_dir`.
    module Ratchet
      extend CommandHelpers

      extend self

      def run(args, stdout:, stderr:, **)
        require "simplecov"
        opts = parse(args, stderr) or return 1
        coverage = CoverageFile.load_coverage(opts.fetch(:input), command: "ratchet", stderr: stderr) or return 1

        outcome, generated = compute(opts, current_floors(coverage))
        AtomicFile.write(opts.fetch(:baseline), outcome.baseline.to_yaml) unless opts.fetch(:dry_run)
        Output.emit(stdout, opts, outcome, generated)
        0
      rescue ConfigurationError => e
        error(stderr, e)
      end

      def parse(args, stderr)
        opts, rest = parse_common(args, init: false, dry_run: false) do |parser, options|
          parser.on("--baseline PATH") { |v| options[:baseline] = v }
          parser.on("--init") { options[:init] = true }
          parser.on("--dry-run") { options[:dry_run] = true }
        end
        return error_nil(stderr, "unexpected argument #{rest.first.inspect}") unless rest.empty?

        opts[:baseline] ||= Dotfile.baseline_file
        opts
      end

      # Only criteria the report carries for a file appear, so a line-only report
      # leaves existing branch floors alone.
      def current_floors(coverage)
        initial = {} #: Baseline::current_floors
        coverage.each_with_object(initial) do |(path, entry), floors|
          criteria = CoverageFile::CRITERIA.filter_map do |criterion, keys|
            percent = entry[keys.fetch(:percent)]
            missed = entry[keys.fetch(:missed)]
            [criterion, {percent: SimpleCov.round_coverage(percent), missed: missed}] if usable?(percent, missed)
          end.to_h
          floors[path] = criteria unless criteria.empty?
        end
      end

      # A report row from another tool may be missing counts; only a complete pair
      # can become a floor.
      def usable?(percent, missed)
        percent.is_a?(Numeric) && missed.instance_of?(Integer)
      end

      def compute(opts, current)
        existing = Baseline.read_if_exists(opts.fetch(:baseline)) unless opts.fetch(:init)
        return [existing.ratchet(current), false] if existing

        none = [] #: Array[String]
        outcome = Baseline::Outcome.new(
          baseline: Baseline.generate(current),
          tightened: none, pruned: none, regressed: none, unchanged: none
        )
        [outcome, true]
      end
    end
  end
end
