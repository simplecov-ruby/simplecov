# frozen_string_literal: true

require_relative "../atomic_file"
require_relative "command_helpers"
require_relative "coverage_file"

module SimpleCov
  module CLI
    # `simplecov ratchet` — rewrite the checked-in per-file coverage
    # baseline (see SimpleCov::Baseline and #1268) from the current
    # report. Floors only ever tighten: a file that improved gets its
    # floor raised, a file that regressed keeps the floor it is now
    # below, entries for files the report no longer carries are pruned,
    # and files without an entry are never given one, so new code stays
    # answerable to the global thresholds rather than to a floor cut at
    # whatever it launched with. `--init` is the escape hatch that
    # regenerates the whole file from the current state, new files and
    # loosened floors included.
    #
    # The baseline path follows the project's `.simplecov`
    # `baseline_file` setting when one is present, the same way the
    # read-only commands follow `coverage_dir`.
    module Ratchet
      extend CommandHelpers

    module_function

      def run(args, stdout:, stderr:, **)
        # The full library carries Baseline and the dotfile default.
        require "simplecov"
        opts = parse(args, stderr) or return 1
        coverage = CoverageFile.load_coverage(opts[:input], command: "ratchet", stderr: stderr) or return 1

        outcome, generated = compute(opts, current_floors(coverage))
        AtomicFile.write(opts[:baseline], outcome.baseline.to_yaml) unless opts[:dry_run]
        emit(stdout, opts, outcome, generated)
        0
      rescue SimpleCov::ConfigurationError => e
        error(stderr, e.message)
      end

      def parse(args, stderr)
        opts, rest = parse_common(args, baseline: nil, init: false, dry_run: false) do |parser, options|
          parser.on("--baseline PATH") { |v| options[:baseline] = v }
          parser.on("--init")          { options[:init] = true }
          parser.on("--dry-run")       { options[:dry_run] = true }
        end
        return error_nil(stderr, "unexpected argument #{rest.first.inspect}") unless rest.empty?

        opts[:baseline] ||= Dotfile.baseline_file
        opts
      end

      # The measured state the floors tighten against, in the shape
      # `Baseline.generate` and `Baseline#ratchet` take. Only criteria
      # the report carries for a file appear, so a line-only report
      # leaves existing branch floors alone.
      def current_floors(coverage)
        initial = {} #: SimpleCov::Baseline::current_floors
        coverage.each_with_object(initial) do |(path, entry), floors|
          criteria = CoverageFile::CRITERIA.filter_map do |criterion, keys|
            percent = entry[keys.fetch(:percent)]
            missed = entry[keys.fetch(:missed)]
            [criterion, {percent: SimpleCov.round_coverage(percent), missed: missed}] if usable?(percent, missed)
          end.to_h
          floors[path] = criteria unless criteria.empty?
        end
      end

      # A report row from another tool may be missing counts; only a
      # complete pair can become a floor.
      def usable?(percent, missed)
        percent.is_a?(Numeric) && missed.is_a?(Integer)
      end

      # Ratchet against the existing baseline, or generate one covering
      # every reported file when there is none (or `--init` asked for a
      # fresh one). The second return value says which happened.
      def compute(opts, current)
        existing = SimpleCov::Baseline.read(opts[:baseline]) unless opts[:init]
        return [existing.ratchet(current), false] if existing

        none = [] #: Array[String]
        outcome = SimpleCov::Baseline::Outcome.new(
          baseline: SimpleCov::Baseline.generate(current),
          tightened: none, pruned: none, regressed: none, unchanged: none
        )
        [outcome, true]
      end

      def emit(stdout, opts, outcome, generated)
        return stdout.puts(JSON.generate(json_summary(opts, outcome, generated))) if opts[:json]

        verb = opts[:dry_run] ? "would write" : "wrote"
        stdout.puts("simplecov ratchet: #{verb} #{opts[:baseline]} (#{change_summary(outcome, generated)})")
        report_regressed(stdout, outcome.regressed)
      end

      def change_summary(outcome, generated)
        files = outcome.baseline.entries.size
        return "#{files} #{files == 1 ? 'file' : 'files'}" if generated

        "#{outcome.tightened.size} tightened, #{outcome.pruned.size} pruned, #{outcome.unchanged.size} unchanged"
      end

      # Floors are kept, not loosened, so a regressed file stays worth
      # saying out loud: running the suite is what shows the failures.
      def report_regressed(stdout, regressed)
        return if regressed.empty?

        noun = regressed.size == 1 ? "1 file below its floor" : "#{regressed.size} files below their floors"
        stdout.puts("simplecov ratchet: #{noun}, entries kept unchanged")
      end

      def json_summary(opts, outcome, generated)
        {
          written: !opts[:dry_run], path: opts[:baseline], generated: generated,
          files: outcome.baseline.entries.size,
          tightened: outcome.tightened, pruned: outcome.pruned,
          regressed: outcome.regressed, unchanged: outcome.unchanged
        }
      end
    end
  end
end
