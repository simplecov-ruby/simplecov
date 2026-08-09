# frozen_string_literal: true

require "json"
require "optparse"
require_relative "command_helpers"

module SimpleCov
  module CLI
    # `simplecov coverage <path>` — print per-criterion stats for one
    # file from a JSONFormatter coverage.json.
    module Coverage
      extend CommandHelpers

    module_function

      def run(args, stdout:, stderr:)
        opts = parse(args, stderr: stderr)
        return 1 unless opts

        match = locate_match(opts, stderr)
        return 1 unless match

        emit(match, opts, stdout)
        0
      end

      def parse(args, stderr:)
        opts = {input: SimpleCov::CLI.default_input, json: false, no_color: false} #: Hash[Symbol, untyped]
        rest = OptionParser.new { |o| common_options(o, opts) }.parse(args)
        return stderr.puts("simplecov coverage: missing file argument") && nil if rest.empty?

        opts[:path] = rest.first
        opts
      end

      def locate_match(opts, stderr)
        coverage = CoverageFile.load_coverage(opts[:input], command: "coverage", stderr: stderr)
        return unless coverage

        match = lookup(coverage, opts[:path])
        return match if match

        stderr.puts("simplecov coverage: no entry for #{opts[:path]} in #{opts[:input]}")
        nil
      end

      # Match either the absolute path, the literal string passed, or
      # any coverage entry whose absolute filename ends with "/<path>".
      # That covers the three natural ways a user types a path: relative
      # to project root ("app/foo.rb"), absolute, or basename-only.
      def lookup(coverage_hash, path)
        absolute = File.expand_path(path)
        suffix   = "/#{path}"
        coverage_hash.find { |fname, _| fname == absolute || fname == path || fname.end_with?(suffix) }
      end

      def emit(match, opts, stdout)
        filename, payload = match
        if opts[:json]
          entry = {filename => payload} #: Hash[untyped, untyped]
          stdout.puts(JSON.pretty_generate(entry))
        else
          print_human(filename, payload, stdout, SimpleCov::CLI.color_enabled?(opts, stdout))
        end
      end

      def print_human(filename, payload, stdout, color)
        stdout.puts(filename)
        CoverageFile::CRITERIA.each_value { |c| emit_criterion(stdout, payload, c, color) }
      end

      def emit_criterion(stdout, payload, criterion, color)
        return unless payload.key?(criterion[:percent])

        pct = payload[criterion[:percent]].to_f
        stdout.puts(stats_row(criterion[:label],
                              SimpleCov::Color.colorize_percent(pct, enabled: color),
                              payload[criterion[:covered]],
                              payload[criterion[:total]]))
      end
    end
  end
end
