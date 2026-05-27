# frozen_string_literal: true

require "json"
require "optparse"
require_relative "report"

module SimpleCov
  module CLI
    # `simplecov uncovered [--threshold N] [--top N]` — list the
    # lowest-coverage files (by line coverage, ascending), so a
    # developer can answer "where should I add tests next?" without
    # opening a browser. Reads coverage.json directly.
    module Uncovered
      DEFAULT_TOP = 10

    module_function

      def run(args, stdout:, stderr:, **)
        opts = parse(args)
        return 1 unless (data = Report.load_data(opts[:input], stderr))

        files = rank(data.fetch("coverage", {}), opts[:threshold]).first(opts[:top])
        return stdout.puts(empty_message(opts[:json])) || 0 if files.empty?

        emit(stdout, files, opts)
        0
      end

      def emit(stdout, files, opts)
        opts[:json] ? emit_json(stdout, files) : emit_text(stdout, files, SimpleCov::CLI.color_enabled?(opts, stdout))
      end

      def parse(args)
        opts = {input: SimpleCov::CLI.default_input, threshold: 100.0, top: DEFAULT_TOP, no_color: false}
        OptionParser.new do |o|
          o.on("--input PATH")         { |v| opts[:input] = v }
          o.on("--threshold N", Float) { |v| opts[:threshold] = v }
          o.on("--top N", Integer)     { |v| opts[:top] = v }
          o.on("--json")               { opts[:json] = true }
          o.on("--no-color")           { opts[:no_color] = true }
        end.parse(args)
        opts
      end

      def emit_text(stdout, files, color)
        files.each { |fname, pct, covered, total| stdout.puts(format_row(fname, pct, covered, total, color)) }
      end

      def emit_json(stdout, files)
        rows = files.map do |fname, pct, covered, total|
          {"file" => fname, "percent" => pct, "covered" => covered, "total" => total}
        end
        stdout.puts(JSON.pretty_generate(rows))
      end

      def empty_message(json)
        json ? "[]" : "simplecov uncovered: nothing to report"
      end

      def rank(coverage_hash, threshold)
        rows = coverage_hash.filter_map { |fname, payload| row_for(fname, payload, threshold) }
        rows.sort_by { |_fname, pct, _c, _t| pct }
      end

      def row_for(fname, payload, threshold)
        return unless payload.is_a?(Hash) && payload["total_lines"].to_i.positive?

        pct = payload["lines_covered_percent"].to_f
        return if pct >= threshold

        [fname, pct, payload["covered_lines"].to_i, payload["total_lines"].to_i]
      end

      def format_row(fname, pct, covered, total, color)
        format("%<pct>s  %<covered>d/%<total>d  %<fname>s",
               pct: SimpleCov::Color.colorize_percent(pct, format("%6.2f%%", pct), enabled: color),
               covered: covered, total: total, fname: fname)
      end
    end
  end
end
