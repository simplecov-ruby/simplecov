# frozen_string_literal: true

require "json"
require "optparse"
require_relative "command_helpers"
require_relative "diff/output"

module SimpleCov
  module CLI
    # `simplecov diff <baseline>`: per-file coverage deltas between coverage.json
    # and a baseline coverage.json checked in alongside the suite. Only files
    # whose coverage moved are listed, and `--fail-on-drop` exits non-zero when
    # any file regressed, so this composes as a "coverage of this PR didn't drop"
    # gate.
    module Diff
      extend CommandHelpers

      # Tolerance below which a delta is considered noise.
      EPSILON = 0.005

      extend self

      def run(args, stdout:, stderr:, **)
        opts = parse(args, stderr)
        return 1 unless opts

        rows = compute_rows(opts.fetch(:current), opts.fetch(:baseline), opts.fetch(:threshold))
        rows.sort_by! { |row| row.fetch(:line_delta) }
        if opts.fetch(:json)
          stdout.puts(JSON.pretty_generate(rows))
        else
          Output.emit_text(stdout, rows, CLI.color_enabled?(opts, stdout))
        end
        (opts.fetch(:fail_on_drop) && coverage_drop?(rows)) ? 1 : 0
      end

      def parse(args, stderr)
        opts = parse_flags(args)
        if opts.fetch(:rest).empty?
          stderr.puts("simplecov diff: missing baseline argument")
          return nil
        end

        opts[:baseline] = load_coverage(opts.fetch(:rest).first, stderr) or return nil
        opts[:current] = load_coverage(opts.fetch(:input), stderr) or return nil
        opts
      end

      def parse_flags(args)
        opts, rest = parse_common(args, fail_on_drop: false, threshold: 0.0) do |o, options|
          o.on("--fail-on-drop") { options[:fail_on_drop] = true }
          o.on("--threshold N", Float) { |v| options[:threshold] = v }
        end
        opts.merge(rest: rest)
      end

      def load_coverage(path, stderr)
        coverage = CoverageFile.load_coverage(path, command: "diff", stderr: stderr)
        return unless coverage

        normalize_keys(coverage)
      end

      # Strips a leading slash so coverage.json files written before the
      # `project_filename` change still diff cleanly against newer reports.
      def normalize_keys(coverage)
        coverage.transform_keys { |key| key.delete_prefix("/") }
      end

      def compute_rows(current, baseline, threshold)
        files = current.keys | baseline.keys
        files.filter_map { |fname| compute_row(fname, current[fname], baseline[fname], threshold) }
      end

      # The threshold is inclusive, so a file that moved exactly N% is listed under
      # `--threshold N`, matching the "at least N%" the usage text promises.
      def compute_row(fname, current_payload, baseline_payload, threshold)
        deltas = compute_deltas(current_payload, baseline_payload)
        floor = threshold.abs
        return nil unless deltas.values.any? { |delta| delta.abs > EPSILON && delta.abs >= floor }

        {file: fname, status: status_for(current_payload, baseline_payload),
         line_delta: deltas.fetch(:line), branch_delta: deltas.fetch(:branch), method_delta: deltas.fetch(:method)}
      end

      def compute_deltas(current_payload, baseline_payload)
        CoverageFile::CRITERIA.transform_values do |fields|
          pct_for(fields, current_payload) - pct_for(fields, baseline_payload)
        end
      end

      def status_for(current_payload, baseline_payload)
        return "added" if baseline_payload.nil?
        return "removed" if current_payload.nil?

        "changed"
      end

      def pct_for(fields, payload)
        return 0.0 unless payload.instance_of?(Hash) && payload[fields.fetch(:total)].to_i.positive?

        payload[fields.fetch(:percent)].to_f
      end

      # A removed file's deltas are all -baseline%, but deleting a covered file is
      # not a coverage regression, so removed rows never trip the gate. Drops are
      # gated on EPSILON like row inclusion and display, so a row listed for a gain
      # in one criterion cannot fail the run over float noise in another.
      def coverage_drop?(rows)
        rows.reject { |row| row.fetch(:status).eql?("removed") }
          .any? { |row| row.fetch_values(:line_delta, :branch_delta, :method_delta).min < -EPSILON }
      end
    end
  end
end
