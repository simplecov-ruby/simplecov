# frozen_string_literal: true

require_relative "command_helpers"
require_relative "patch/changed_lines"
require_relative "patch/output"

module SimpleCov
  module CLI
    # `simplecov patch [--base REF]`: line coverage over only the lines a
    # change touched. Where `diff` asks "did the number move" and needs a
    # baseline artifact, `patch` asks the question a reviewer actually asks: is
    # the code in this change tested? A project sitting at 40% cannot move its
    # global number in one pull request, but it can insist that every line it
    # adds is covered.
    #
    # Only files the report already carries are scored: a changed file
    # SimpleCov never tracked is out of scope, and a line `LinesClassifier`
    # considers never relevant stays out of the denominator the same way it
    # stays out of the file total.
    #
    module Patch
      extend CommandHelpers

      extend self

      def run(args, stdout:, stderr:, **)
        opts = parse(args, stderr)
        return 1 unless opts

        # An omitted --base resolves through origin's HEAD, so master and trunk
        # repositories work bare; in CI, pass the pull request's target branch
        # explicitly.
        opts[:base] ||= Git.default_base
        diffed = ChangedLines.call(opts.fetch(:base), find_renames: opts.fetch(:find_renames), stderr: stderr)
        return 1 unless diffed

        rows = compute_rows(opts.fetch(:coverage), diffed, stderr)
        Output.emit(stdout, rows, opts)
        Output.gate(rows, opts.fetch(:minimum))
      end

      def parse(args, stderr)
        # No `base:` default: the run fills it in from the repository when the
        # option is left out.
        opts, rest = parse_common(args, find_renames: false, minimum: nil) do |parser, options|
          parser.on("--base REF") { |v| options[:base] = v }
          parser.on("--minimum N", Float) { |v| options[:minimum] = v }
          parser.on("--find-renames") { options[:find_renames] = true }
        end
        return unless positional_ok?(rest, stderr)

        opts[:coverage] = CoverageFile.load_coverage(opts.fetch(:input), command: "patch", stderr: stderr) or return nil
        opts
      end

      # A stray positional looks exactly like a ref, so a forgotten `--base`
      # (`simplecov patch feature-x`) would otherwise diff against the default
      # and gate the wrong change in silence.
      def positional_ok?(rest, stderr)
        return true if rest.empty?

        error(stderr, "unexpected argument #{rest.first.inspect} (did you mean `--base #{rest.first}`?)")
        false
      end

      # Everything below reads values that came out of a coverage.json, which
      # carries plain objects, arrays and integers and never a subclass of one,
      # so the shape checks ask about the class itself.

      # Diff paths are exact root-relative names, so they resolve exactly against
      # the report. The suffix fallback `CoverageFile.lookup` offers interactive
      # commands could only ever bind a changed file the report doesn't carry to
      # some other file's hits and score the wrong entry.
      def compute_rows(coverage, diffed, stderr)
        index = CoverageFile.exact_index(coverage)
        diffed.fetch(:changes).filter_map do |path, lines|
          payload = index[File.expand_path(path, diffed.fetch(:root))] || index[path]
          next unless payload.instance_of?(Hash) # file the report doesn't carry -> out of scope

          changed = changed_for(lines, payload)
          warn_stale(path, payload, changed, stderr)
          row = build_row(path, payload, changed)
          row if scored?(row) # nothing coverable changed in this file
        end
      end

      # An untracked file appears in no diff, so `:all` stands in for its line
      # numbers: every line the report knows is this change's work.
      def changed_for(lines, payload)
        return lines.uniq unless lines.equal?(:all)

        hits = payload["lines"]
        hits.instance_of?(Array) ? (1..hits.length).to_a : []
      end

      # A changed line past the end of the report's lines array reads as
      # never-relevant and silently drops out of the denominator, which is right
      # for a fresh report and wrong for a stale one, so say which is likelier
      # out loud instead of letting a `--minimum` gate pass vacuously.
      def warn_stale(path, payload, changed, stderr)
        hits = payload["lines"]
        return unless hits.instance_of?(Array)
        return if changed.empty? || changed.max <= hits.length

        stderr.puts("simplecov patch: #{path} changed beyond the #{hits.length}-line entry in the " \
                    "report (is the report stale? regenerate it and rerun)")
      end

      def build_row(path, payload, changed)
        {
          file: path,
          line: line_stats(payload["lines"], changed),
          branch: entry_stats(payload["branches"], changed),
          method: entry_stats(payload["methods"], changed)
        }
      end

      # A line counts only where the report gives it an Integer hit count; a
      # never-relevant line (nil) or a `:nocov:` line ("ignored") stays out of
      # the denominator, the same rule the file total uses.
      def line_stats(hits, changed)
        covered = 0
        missing = [] #: Array[Integer]
        return {covered: covered, relevant: 0, missing: missing} unless hits.instance_of?(Array)

        changed.each do |number|
          hit = hits.at(number - 1)
          # nil / "ignored" (nocov) / any non-Integer -> never relevant, skipped.
          next unless hit.instance_of?(Integer)

          hit.positive? ? (covered += 1) : (missing << number)
        end
        {covered: covered, relevant: covered + missing.size, missing: missing.sort}
      end

      # Branches and methods share the report shape (a reported line and an
      # integer hit count), so one scorer serves both. nil when the report
      # carries no data for the criterion, so the output and gate skip it
      # rather than reporting a hollow 0/0. A miss is recorded at the reported
      # line so the note points where the source is.
      def entry_stats(entries, changed)
        return nil unless entries.instance_of?(Array)

        covered = 0
        missing = [] #: Array[Integer]
        each_touched(entries, changed) do |line, hits|
          hits.positive? ? (covered += 1) : (missing << line)
        end
        {covered: covered, relevant: covered + missing.size, missing: missing.uniq.sort}
      end

      # "ignored" (nocov) entries and entries off the change are skipped.
      def each_touched(entries, changed)
        entries.each do |entry|
          next unless entry.instance_of?(Hash)

          line = entry["report_line"] || entry["start_line"]
          hits = entry["coverage"]
          yield line, hits if changed.include?(line) && hits.instance_of?(Integer)
        end
      end

      def scored?(row)
        row.fetch(:line).fetch(:relevant).positive? ||
          Output.measured?(row.fetch(:branch)) || Output.measured?(row.fetch(:method))
      end
    end
  end
end
