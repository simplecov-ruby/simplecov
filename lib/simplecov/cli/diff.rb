# frozen_string_literal: true

require "json"
require "optparse"

module SimpleCov
  module CLI
    # `simplecov diff <baseline>` — print the per-file line-coverage
    # delta between coverage.json (--input) and a baseline coverage.json
    # checked in alongside the suite. Only files whose coverage moved
    # are listed; --fail-on-drop exits non-zero when any file regressed,
    # so this composes with CI as a "coverage of this PR didn't drop"
    # gate. Resolves the long-standing "diff coverage" feature request.
    module Diff
      EPSILON = 0.005 # tolerance below which a delta is considered noise

      # Per-criterion key map. coverage.json carries `lines_covered_percent`
      # plus `branches_covered_percent` / `methods_covered_percent` when
      # the corresponding criterion is enabled, so the diff can describe
      # whichever criteria the baseline + current both report on.
      CRITERIA = %i[lines branches methods].freeze
      CRITERION_FIELDS = {
        lines: {pct: "lines_covered_percent", total: "total_lines"},
        branches: {pct: "branches_covered_percent", total: "total_branches"},
        methods: {pct: "methods_covered_percent", total: "total_methods"}
      }.freeze

      STATUS_SUFFIX = {"added" => "(new file)", "removed" => "(removed)"}.freeze

    module_function

      def run(args, stdout:, stderr:, **)
        opts = parse(args, stderr)
        return 1 unless opts

        rows = compute_rows(opts[:current], opts[:baseline], opts[:threshold])
        rows.sort_by! { |row| row[:line_delta] }
        if opts[:json]
          emit_json(stdout, rows)
        else
          emit_text(stdout, rows, SimpleCov::CLI.color_enabled?(opts, stdout))
        end
        opts[:fail_on_drop] && rows.any? { |row| row[:line_delta].negative? } ? 1 : 0
      end

      def parse(args, stderr)
        opts = parse_flags(args)
        return stderr.puts("simplecov diff: missing baseline argument") && nil if opts[:rest].empty?

        opts[:baseline] = load_coverage(opts[:rest].first, stderr) or return nil
        opts[:current]  = load_coverage(opts[:input], stderr) or return nil
        opts
      end

      def parse_flags(args)
        opts = {input: SimpleCov::CLI.default_input, fail_on_drop: false, json: false, threshold: 0.0, no_color: false}
        opts.merge(rest: option_parser(opts).parse(args))
      end

      def option_parser(opts)
        OptionParser.new do |o|
          o.on("--input PATH")         { |v| opts[:input] = v }
          o.on("--fail-on-drop")       { opts[:fail_on_drop] = true }
          o.on("--json")               { opts[:json] = true }
          o.on("--threshold N", Float) { |v| opts[:threshold] = v }
          o.on("--no-color")           { opts[:no_color] = true }
        end
      end

      def load_coverage(path, stderr)
        no_coverage = {} #: Hash[String, untyped]
        return normalize_keys(JSON.parse(File.read(path)).fetch("coverage", no_coverage)) if File.exist?(path)

        stderr.puts("simplecov diff: #{path} not found")
        nil
      end

      # Strip a leading slash so coverage.json files written before the
      # `project_filename` change (keys like "/lib/foo.rb") still diff
      # cleanly against newer reports (keys like "lib/foo.rb").
      def normalize_keys(coverage)
        coverage.transform_keys { |key| key.delete_prefix("/") }
      end

      def compute_rows(current, baseline, threshold)
        files = current.keys | baseline.keys
        files.filter_map { |fname| compute_row(fname, current[fname], baseline[fname], threshold) }
      end

      def compute_row(fname, current_payload, baseline_payload, threshold)
        deltas = CRITERIA.to_h { |c| [c, pct_for(c, current_payload) - pct_for(c, baseline_payload)] }
        floor = [threshold.abs, EPSILON].max
        return nil unless deltas.values.any? { |delta| delta.abs > floor }

        {
          file: fname,
          status: status_for(current_payload, baseline_payload),
          line_delta: deltas[:lines],
          branch_delta: deltas[:branches],
          method_delta: deltas[:methods]
        }
      end

      def status_for(current_payload, baseline_payload)
        return "added"   if baseline_payload.nil?
        return "removed" if current_payload.nil?

        "changed"
      end

      def pct_for(criterion, payload)
        fields = CRITERION_FIELDS.fetch(criterion)
        return 0.0 unless payload.is_a?(Hash) && payload[fields[:total]].to_i.positive?

        payload[fields[:pct]].to_f
      end

      def emit_text(stdout, rows, color)
        return stdout.puts("simplecov diff: no per-file coverage changes") if rows.empty?

        rows.each { |row| stdout.puts(format_row(row, color)) }
      end

      def format_row(row, color)
        line = "  #{delta_parts(row, color).join('  ')}  #{row[:file]}"
        suffix = STATUS_SUFFIX[row[:status]]
        suffix ? "#{line}  #{suffix}" : line
      end

      def delta_parts(row, color)
        [
          format_delta(row[:line_delta], "lines", color),
          (format_delta(row[:branch_delta], "branches", color) if row[:branch_delta].abs > EPSILON),
          (format_delta(row[:method_delta], "methods", color)  if row[:method_delta].abs > EPSILON)
        ].compact
      end

      # Deltas are sign-based, not threshold-based: a +5% bump is good
      # (green) and a -5% drop is bad (red), regardless of where the
      # absolute coverage level lands.
      def format_delta(delta, label, color)
        sign = delta.positive? ? "+" : ""
        text = format("%<sign>s%<delta>6.2f%% %<label>s", sign: sign, delta: delta, label: label)
        SimpleCov::Color.colorize(text, delta.negative? ? :red : :green, enabled: color)
      end

      def emit_json(stdout, rows)
        stdout.puts(JSON.pretty_generate(rows))
      end
    end
  end
end
