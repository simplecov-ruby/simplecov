# frozen_string_literal: true

require "json"
require "optparse"
require_relative "report"

module SimpleCov
  module CLI
    # `simplecov uncovered [--threshold N] [--top N] [--criterion C]` — list
    # the lowest-coverage files (by the chosen criterion, ascending), so a
    # developer can answer "where should I add tests next?" without
    # opening a browser. Reads coverage.json directly.
    module Uncovered
      DEFAULT_TOP = 10

      # The coverage.json fields backing each criterion.
      CRITERION_KEYS = {
        line: {percent: "lines_covered_percent", covered: "covered_lines", total: "total_lines"},
        branch: {percent: "branches_covered_percent", covered: "covered_branches", total: "total_branches"},
        method: {percent: "methods_covered_percent", covered: "covered_methods", total: "total_methods"}
      }.freeze

    module_function

      def run(args, stdout:, stderr:, **)
        opts = parse(args)
        keys = CRITERION_KEYS[opts[:criterion]]
        return unknown_criterion(opts[:criterion], stderr) unless keys

        report(opts, keys, stdout, stderr)
      end

      def report(opts, keys, stdout, stderr)
        return 1 unless (data = Report.load_data(opts[:input], stderr))

        none = {} #: Hash[String, untyped]
        files = rank(data.fetch("coverage", none), opts[:threshold], keys).first(opts[:top])
        return stdout.puts(empty_message(opts[:json])) || 0 if files.empty?

        emit(stdout, files, opts)
        0
      end

      def unknown_criterion(criterion, stderr)
        stderr.puts("simplecov uncovered: unknown --criterion #{criterion.inspect} (expected line, branch, or method)")
        1
      end

      def emit(stdout, files, opts)
        opts[:json] ? emit_json(stdout, files) : emit_text(stdout, files, SimpleCov::CLI.color_enabled?(opts, stdout))
      end

      def parse(args)
        opts = {input: SimpleCov::CLI.default_input, threshold: 100.0, top: DEFAULT_TOP, criterion: :line, no_color: false}
        build_parser(opts).parse(args)
        opts
      end

      # Option parsing with per-flag coercions is inherently ABC-heavy; the
      # metric is noise here.
      def build_parser(opts) # rubocop:disable Metrics/AbcSize
        OptionParser.new do |o|
          o.on("--input PATH")         { |v| opts[:input] = v }
          o.on("--threshold N", Float) { |v| opts[:threshold] = v }
          o.on("--top N", Integer)     { |v| opts[:top] = v }
          o.on("--criterion C")        { |v| opts[:criterion] = v.to_sym }
          o.on("--json")               { opts[:json] = true }
          o.on("--no-color")           { opts[:no_color] = true }
        end
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

      def rank(coverage_hash, threshold, keys)
        rows = coverage_hash.filter_map { |fname, payload| row_for(fname, payload, threshold, keys) }
        rows.sort_by { |_fname, pct, _c, _t| pct }
      end

      def row_for(fname, payload, threshold, keys)
        return unless payload.is_a?(Hash) && payload[keys[:total]].to_i.positive?

        pct = payload[keys[:percent]].to_f
        return if pct >= threshold

        [fname, pct, payload[keys[:covered]].to_i, payload[keys[:total]].to_i]
      end

      def format_row(fname, pct, covered, total, color)
        format("%<pct>s  %<covered>d/%<total>d  %<fname>s",
               pct: SimpleCov::Color.colorize_percent(pct, format("%6.2f%%", pct), enabled: color),
               covered: covered, total: total, fname: fname)
      end
    end
  end
end
