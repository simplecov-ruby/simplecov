# frozen_string_literal: true

require "json"
require "optparse"

module SimpleCov
  module CLI
    # `simplecov coverage <path>` — print per-criterion stats for one
    # file from a JSONFormatter coverage.json.
    module Coverage
      CRITERIA = [
        {label: "Line",   pct: "lines_covered_percent",    cov: "covered_lines",    tot: "total_lines"},
        {label: "Branch", pct: "branches_covered_percent", cov: "covered_branches", tot: "total_branches"},
        {label: "Method", pct: "methods_covered_percent",  cov: "covered_methods",  tot: "total_methods"}
      ].freeze

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
        opts = {input: SimpleCov::CLI.default_input, json: false, no_color: false}
        rest =
          OptionParser.new do |o|
            o.on("--input PATH") { |v| opts[:input] = v }
            o.on("--json") { opts[:json] = true }
            o.on("--no-color") { opts[:no_color] = true }
          end.parse(args)
        return stderr.puts("simplecov coverage: missing file argument") && nil if rest.empty?

        opts[:path] = rest.first
        opts
      end

      def locate_match(opts, stderr)
        return stderr.puts("simplecov coverage: #{opts[:input]} not found") && nil unless File.exist?(opts[:input])

        data = JSON.parse(File.read(opts[:input]))
        match = lookup(data.fetch("coverage", {}), opts[:path])
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
        coverage_hash.each do |fname, payload|
          return [fname, payload] if fname == absolute || fname == path || fname.end_with?(suffix)
        end
        nil
      end

      def emit(match, opts, stdout)
        filename, payload = match
        if opts[:json]
          stdout.puts(JSON.pretty_generate(filename => payload))
        else
          print_human(filename, payload, stdout, SimpleCov::CLI.color_enabled?(opts, stdout))
        end
      end

      def print_human(filename, payload, stdout, color)
        stdout.puts(filename)
        CRITERIA.each { |c| emit_criterion(stdout, payload, c, color) }
      end

      def emit_criterion(stdout, payload, criterion, color)
        return unless payload.key?(criterion[:pct])

        pct = payload[criterion[:pct]].to_f
        stdout.puts(format("  %<label>-7s %<pct>s (%<covered>d / %<total>d)",
                           label: "#{criterion[:label]}:",
                           pct: SimpleCov::Color.colorize_percent(pct, enabled: color),
                           covered: payload[criterion[:cov]] || 0,
                           total: payload[criterion[:tot]] || 0))
      end
    end
  end
end
