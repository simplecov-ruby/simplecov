# frozen_string_literal: true

require "json"
require "optparse"
require_relative "command_helpers"
require_relative "patch/output"
require_relative "show/annotator"
require_relative "uncovered/misses"

module SimpleCov
  module CLI
    # `simplecov uncovered`: the lowest-coverage files by the chosen criterion,
    # ascending, so a developer can answer "where should I add tests next?"
    # without opening a browser.
    module Uncovered
      extend CommandHelpers

      DEFAULT_TOP = 10

      extend self

      def run(args, stdout:, stderr:, **)
        opts = parse(args)
        issue = precheck(opts)
        return error(stderr, issue) if issue

        keys = CoverageFile::CRITERIA[opts.fetch(:criterion)]
        return unknown_criterion(opts.fetch(:criterion), stderr) unless keys

        opts[:missing] = true if opts.fetch(:annotate)
        report(opts, keys, stdout, stderr)
      end

      def precheck(opts)
        return nil unless opts.fetch(:annotate)
        unless opts.fetch(:annotate).eql?("github")
          return "unknown --annotate #{opts.fetch(:annotate).inspect} (only github is supported)"
        end

        "cannot combine --annotate with --json" if opts.fetch(:json)
      end

      def report(opts, keys, stdout, stderr)
        coverage = CoverageFile.load_coverage(opts.fetch(:input), command: "uncovered", stderr: stderr)
        return 1 unless coverage

        files = rank(coverage, opts, keys).first(opts.fetch(:top))
        return empty(opts, stdout) if files.empty?

        emit(stdout, files, opts)
        0
      end

      def empty(opts, stdout)
        stdout.puts(empty_message(opts.fetch(:json))) unless opts.fetch(:annotate)
        0
      end

      def unknown_criterion(criterion, stderr)
        stderr.puts("simplecov uncovered: unknown --criterion #{criterion.inspect} (expected line, branch, or method)")
        1
      end

      def emit(stdout, files, opts)
        return Misses.annotate(stdout, files) if opts.fetch(:annotate)

        opts.fetch(:json) ? emit_json(stdout, files) : emit_text(stdout, files, CLI.color_enabled?(opts, stdout))
      end

      def parse(args)
        opts, = parse_common(args, threshold: 100.0, top: DEFAULT_TOP, criterion: :line,
                                   missing: false, annotate: nil) { |o, options| own_options(o, options) }
        opts
      end

      def own_options(parser, options)
        parser.on("--threshold N", Float) { |v| options[:threshold] = v }
        parser.on("--top N", Integer)     { |v| options[:top] = validate_top(v) }
        parser.on("--criterion C")        { |v| options[:criterion] = v.to_sym }
        parser.on("--missing")            { options[:missing] = true }
        parser.on("--annotate KIND")      { |v| options[:annotate] = v }
      end

      # A negative count would raise from `Array#first`, so it is reported as the
      # parse error it is. `--top 0` is allowed and shows nothing. OptionParser
      # prepends the offending option's name, so the raise carries only the reason.
      def validate_top(value)
        raise OptionParser::InvalidArgument, "must not be negative" if value.negative?

        value
      end

      def emit_text(stdout, files, color)
        files.each do |fname, pct, covered, total, missed|
          row = format_row(fname, pct, covered, total, color)
          row += "  missing #{Patch::Output.ranges(missed, ',')}" if missed&.any?
          stdout.puts(row)
        end
      end

      def emit_json(stdout, files)
        rows = files.map do |fname, pct, covered, total, missed|
          row = {"file" => fname, "percent" => pct, "covered" => covered, "total" => total}
          row["missing"] = missed if missed
          row
        end
        stdout.puts(JSON.pretty_generate(rows))
      end

      def empty_message(json)
        json ? "[]" : "simplecov uncovered: nothing to report"
      end

      def rank(coverage_hash, opts, keys)
        rows = coverage_hash.filter_map { |fname, payload| row_for(fname, payload, opts, keys) }
        rows.sort_by { |_fname, pct, _c, _t| pct }
      end

      def row_for(fname, payload, opts, keys)
        return unless payload.instance_of?(Hash) && payload[keys.fetch(:total)].to_i.positive?

        pct = payload[keys.fetch(:percent)].to_f
        return if pct >= opts.fetch(:threshold)

        build_row(fname, pct, payload, opts, keys)
      end

      def build_row(fname, pct, payload, opts, keys)
        row = [fname, pct, payload[keys.fetch(:covered)].to_i, payload.fetch(keys.fetch(:total)).to_i]
        row << Misses.missed_for(payload, opts.fetch(:criterion)) if opts.fetch(:missing)
        row
      end

      def format_row(fname, pct, covered, total, color)
        format("%<pct>s  %<covered>d/%<total>d  %<fname>s",
               pct: Color.colorize_percent(pct, format("%6.2f%%", pct), enabled: color),
               covered: covered, total: total, fname: fname)
      end
    end
  end
end
