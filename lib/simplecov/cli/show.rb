# frozen_string_literal: true

require "json"
require "optparse"
require_relative "command_helpers"
require_relative "patch/output"
require_relative "show/annotator"
require_relative "show/sweep"

module SimpleCov
  module CLI
    # `simplecov show <path>`: annotated source in the terminal, the way
    # `go tool cover` and `llvm-cov show` print it. `--uncovered-only` collapses
    # the answer to `path:ranges`, a form that greps, fits in a commit message,
    # and hands a coding agent exactly the lines whose tests are missing.
    module Show
      extend CommandHelpers

      extend self

      def run(args, stdout:, stderr:)
        opts = parse(args)
        return run_project(opts, stdout, stderr) unless opts.fetch(:path)

        coverage = CoverageFile.load_coverage(opts.fetch(:input), command: "show", stderr: stderr)
        return 1 unless coverage

        located = locate_or_report(coverage, opts, stderr)
        return 1 unless located

        render(located, opts, stdout, stderr)
      end

      # No path sweeps the whole project, in the compact forms only. The annotated
      # text form still wants one file.
      def run_project(opts, stdout, stderr)
        unless opts.fetch(:uncovered_only) || opts.fetch(:json)
          return error(stderr, "missing path (annotating needs one file; --uncovered-only sweeps the whole project)")
        end

        coverage = CoverageFile.load_coverage(opts.fetch(:input), command: "show", stderr: stderr)
        return 1 unless coverage

        Sweep.emit(Sweep.misses(coverage), opts, stdout, stderr)
      end

      def parse(args)
        opts = {input: CLI.default_input, no_color: false,
                uncovered_only: false, json: false} #: Hash[Symbol, untyped]
        rest = build_parser { |parser| options(parser, opts) }.parse(args)
        opts[:path] = rest.first
        opts
      end

      def options(parser, opts)
        parser.on("--input PATH")     { |v| opts[:input] = v }
        parser.on("--no-color")       { opts[:no_color] = true }
        parser.on("--uncovered-only") { opts[:uncovered_only] = true }
        parser.on("--json")           { opts[:json] = true }
      end

      # A line-less report has no per-line hits to put in a gutter, so it is
      # reported like an unresolvable path is.
      def locate_or_report(coverage, opts, stderr)
        path, input = opts.fetch_values(:path, :input)
        match = CoverageFile.lookup(coverage, path)
        return error_nil(stderr, CoverageFile.not_found_message(coverage, path, input)) unless match

        entry = match.last
        unless entry.instance_of?(Hash)
          return CoverageFile.report_invalid(stderr, "show", input, "entry for #{path} must be an object")
        end
        return match if entry["lines"].instance_of?(Array)

        error_nil(stderr, "no line coverage for #{path} in #{input}")
      end

      def render(located, opts, stdout, stderr)
        filename, entry = located
        return emit_json(entry, opts, stdout) if opts.fetch(:json)
        return show_uncovered(entry, opts, stdout, stderr) if opts.fetch(:uncovered_only)

        source = source_for(filename, entry, opts, stderr)
        return 1 unless source

        Annotator.call(source, entry, stdout, color: CLI.color_enabled?(opts, stdout))
        0
      end

      def emit_json(entry, opts, stdout)
        stdout.puts(JSON.pretty_generate(
                      path: opts.fetch(:path), missed: Annotator.missed_lines(entry),
                      lines: relevant_lines(entry), markers: Annotator.markers_for(entry)
                    ))
        0
      end

      def relevant_lines(entry)
        entry.fetch("lines").each_with_index.filter_map do |hit, index|
          {number: index + 1, hits: hit} if hit.instance_of?(Integer)
        end
      end

      def show_uncovered(entry, opts, stdout, stderr)
        missed = Annotator.missed_lines(entry)
        if missed.empty?
          stderr.puts("simplecov show: nothing uncovered in #{opts.fetch(:path)}")
        else
          stdout.puts("#{opts.fetch(:path)}:#{Patch::Output.ranges(missed, ',')}")
        end
        0
      end

      # The report's own source when it carries one; otherwise the file on disk,
      # accepted only while its line count still matches the report's, since
      # annotating drifted source would put hit counts on the wrong lines.
      def source_for(filename, entry, opts, stderr)
        embedded = entry["source"]
        return embedded if embedded.instance_of?(Array) && embedded.all?(String)
        unless File.file?(filename)
          return error_nil(stderr, "no source for #{opts.fetch(:path)} in #{opts.fetch(:input)} and no file " \
                                   "at #{filename}, regenerate the report with `source_in_json true`")
        end

        lines = File.readlines(filename, chomp: true)
        return lines if lines.size.eql?(entry.fetch("lines").size)

        error_nil(stderr, "#{filename} has changed since the report (#{lines.size} lines now, " \
                          "#{entry.fetch('lines').size} recorded), regenerate the report")
      end
    end
  end
end
