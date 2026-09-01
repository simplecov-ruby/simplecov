# frozen_string_literal: true

require "json"
require "optparse"
require_relative "command_helpers"

module SimpleCov
  module CLI
    module Coverage
      extend CommandHelpers

      extend self

      def run(args, stdout:, stderr:)
        opts = parse(args, stderr: stderr)
        return 1 unless opts

        match = locate_match(opts, stderr)
        return 1 unless match

        emit(match, opts, stdout)
        0
      end

      def parse(args, stderr:)
        opts, rest = parse_common(args)
        if rest.empty?
          stderr.puts("simplecov coverage: missing file argument")
          return nil
        end

        opts[:path] = rest.first
        opts
      end

      def locate_match(opts, stderr)
        coverage = CoverageFile.load_coverage(opts.fetch(:input), command: "coverage", stderr: stderr)
        return unless coverage

        match = lookup(coverage, opts.fetch(:path))
        return report_not_found(stderr, coverage, opts) if match.nil?
        return match if match.last.instance_of?(Hash)

        CoverageFile.report_invalid(stderr, "coverage", opts.fetch(:input),
          "entry for #{opts.fetch(:path)} must be an object")
      end

      def report_not_found(stderr, coverage, opts)
        message = CoverageFile.not_found_message(coverage, opts.fetch(:path), opts.fetch(:input))
        stderr.puts("simplecov coverage: #{message}")
      end

      def lookup(coverage_hash, path)
        CoverageFile.lookup(coverage_hash, path)
      end

      def emit(match, opts, stdout)
        filename, payload = match
        if opts.fetch(:json)
          entry = {filename => payload} #: Hash[untyped, untyped]
          stdout.puts(JSON.pretty_generate(entry))
        else
          print_human(filename, payload, stdout, CLI.color_enabled?(opts, stdout))
        end
      end

      def print_human(filename, payload, stdout, color)
        stdout.puts(filename)
        CoverageFile::CRITERIA.each_value { |c| emit_criterion(stdout, payload, c, color) }
      end

      def emit_criterion(stdout, payload, criterion, color)
        return unless payload.key?(criterion.fetch(:percent))

        pct = payload.fetch(criterion.fetch(:percent)).to_f
        stdout.puts(stats_row(criterion.fetch(:label),
          Color.colorize_percent(pct, enabled: color),
          payload[criterion.fetch(:covered)],
          payload[criterion.fetch(:total)]))
      end
    end
  end
end
