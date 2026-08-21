# frozen_string_literal: true

require "optparse"
require_relative "command_helpers"
require_relative "patch/output"
require_relative "show/annotator"

module SimpleCov
  module CLI
    # `simplecov show <path>` — annotated source in the terminal, the
    # way `go tool cover` and `llvm-cov show` print it: hit counts in
    # the gutter, misses called out under their lines, and branch and
    # method misses annotated the same way when the report measured
    # them. `--uncovered-only` collapses the answer to `path:ranges`,
    # a form that greps, fits in a commit message, and hands a coding
    # agent exactly the lines whose tests are missing.
    module Show
      extend CommandHelpers

    module_function

      def run(args, stdout:, stderr:)
        opts = parse(args)
        return error(stderr, "missing path (usage: simplecov show <path>)") unless opts[:path]

        coverage = CoverageFile.load_coverage(opts[:input], command: "show", stderr: stderr)
        return 1 unless coverage

        located = locate(coverage, opts, stderr)
        return 1 unless located

        render(located, opts, stdout, stderr)
      end

      # The common trio minus --json: stdout is the annotation itself.
      def parse(args)
        opts = {input: SimpleCov::CLI.default_input, no_color: false, uncovered_only: false} #: Hash[Symbol, untyped]
        rest =
          OptionParser.new do |parser|
            parser.on("--input PATH")     { |v| opts[:input] = v }
            parser.on("--no-color")       { opts[:no_color] = true }
            parser.on("--uncovered-only") { opts[:uncovered_only] = true }
          end.parse(args)
        opts[:path] = rest.first
        opts
      end

      # [filename, entry] for the resolved path, nil after reporting an
      # unresolvable path, a wrong-typed entry, or a line-less report
      # (a branch-only report has no per-line hits to put in a gutter).
      def locate(coverage, opts, stderr)
        match = CoverageFile.lookup(coverage, opts[:path])
        return error_nil(stderr, CoverageFile.not_found_message(coverage, opts[:path], opts[:input])) unless match

        entry = match.last
        unless entry.is_a?(Hash)
          return CoverageFile.report_invalid(stderr, "show", opts[:input], "entry for #{opts[:path]} must be an object")
        end
        return match if entry["lines"].is_a?(Array)

        error_nil(stderr, "no line coverage for #{opts[:path]} in #{opts[:input]}")
      end

      def render(located, opts, stdout, stderr)
        filename, entry = located
        return show_uncovered(entry, opts, stdout, stderr) if opts[:uncovered_only]

        source = source_for(filename, entry, opts, stderr)
        return 1 unless source

        Annotator.call(source, entry, stdout, color: SimpleCov::CLI.color_enabled?(opts, stdout))
        0
      end

      def show_uncovered(entry, opts, stdout, stderr)
        missed = Annotator.missed_lines(entry)
        if missed.empty?
          stderr.puts("simplecov show: nothing uncovered in #{opts[:path]}")
        else
          stdout.puts("#{opts[:path]}:#{Patch::Output.ranges(missed, ',')}")
        end
        0
      end

      # The report's own source when it carries one; otherwise the file
      # on disk, accepted only while its line count still matches the
      # report's, since annotating drifted source would put hit counts
      # on the wrong lines.
      def source_for(filename, entry, opts, stderr)
        embedded = entry["source"]
        return embedded if embedded.is_a?(Array) && embedded.all?(String)
        unless File.file?(filename)
          return error_nil(stderr, "no source for #{opts[:path]} in #{opts[:input]} and no file at #{filename}, " \
                                   "regenerate the report with `source_in_json true`")
        end

        lines = File.readlines(filename, chomp: true)
        return lines if lines.size == entry["lines"].size

        error_nil(stderr, "#{filename} has changed since the report (#{lines.size} lines now, " \
                          "#{entry['lines'].size} recorded), regenerate the report")
      end
    end
  end
end
