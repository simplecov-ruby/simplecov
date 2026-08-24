# frozen_string_literal: true

require_relative "command_helpers"
require_relative "patch/changed_lines"
require_relative "patch/output"

module SimpleCov
  module CLI
    # `simplecov patch [--base REF]` — report line coverage over only the
    # lines a change touched. Where `diff` asks "did the number move" and
    # needs a baseline artifact, `patch` asks the question a reviewer
    # actually asks: is the code in this change tested? A project sitting
    # at 40% cannot move its global number in one pull request, but it can
    # insist that every line it adds is covered.
    #
    # It reads `git diff --unified=0 --merge-base <base>`, intersects the
    # added and modified line numbers with the current report (--input),
    # and prints coverage over just those lines. `--minimum N` exits
    # non-zero below a floor, so it composes as a CI gate alongside the
    # existing threshold checks, and `--json` emits rows the way the other
    # read-only commands do.
    #
    # Only files the report already carries are scored: a changed file
    # SimpleCov never tracked (a non-Ruby file, or one outside the
    # configured `cover` / `track_files` set) is out of scope, and a line
    # `LinesClassifier` considers never relevant (blank or comment) stays
    # out of the denominator the same way it stays out of the file total.
    #
    module Patch
      extend CommandHelpers

    module_function

      def run(args, stdout:, stderr:, **)
        opts = parse(args, stderr)
        return 1 unless opts

        # An omitted --base resolves through origin's HEAD, so master
        # and trunk repositories work bare; in CI, pass the pull
        # request's target branch (or its merge-base) explicitly.
        opts[:base] ||= Git.default_base
        diffed = ChangedLines.call(opts[:base], find_renames: opts[:find_renames], stderr: stderr)
        return 1 unless diffed

        rows = compute_rows(opts[:coverage], diffed, stderr)
        Output.emit(stdout, rows, opts)
        Output.gate(rows, opts[:minimum])
      end

      def parse(args, stderr)
        opts, rest = parse_common(args, base: nil, find_renames: false, minimum: nil) do |parser, options|
          parser.on("--base REF") { |v| options[:base] = v }
          parser.on("--minimum N", Float) { |v| options[:minimum] = v }
          parser.on("--find-renames") { options[:find_renames] = true }
        end
        return unless positional_ok?(rest, stderr)

        opts[:coverage] = CoverageFile.load_coverage(opts[:input], command: "patch", stderr: stderr) or return nil
        opts
      end

      # A stray positional looks exactly like a ref, so a forgotten `--base`
      # (`simplecov patch feature-x`) would otherwise diff against the
      # default and gate the wrong change in silence.
      def positional_ok?(rest, stderr)
        return true if rest.empty?

        error(stderr, "unexpected argument #{rest.first.inspect} (did you mean `--base #{rest.first}`?)")
        false
      end

      # --- coverage intersection ---------------------------------------

      # Diff paths are exact root-relative names, so they resolve exactly
      # against the report — the suffix fallback `CoverageFile.lookup`
      # offers interactive commands could only ever bind a changed file
      # the report doesn't carry to some *other* file's hits and score
      # the wrong entry.
      def compute_rows(coverage, diffed, stderr)
        index = CoverageFile.exact_index(coverage)
        diffed[:changes].filter_map do |path, lines|
          payload = index[File.expand_path(path, diffed[:root])] || index[path]
          next unless payload.is_a?(Hash) # file the report doesn't carry -> out of scope

          changed = changed_for(lines, payload)
          warn_stale(path, payload, changed, stderr)
          row = build_row(path, payload, changed)
          row if scored?(row) # nothing coverable changed in this file
        end
      end

      # An untracked file appears in no diff, so `:all` stands in for its
      # line numbers: every line the report knows is this change's work.
      def changed_for(lines, payload)
        return lines.uniq unless lines == :all

        hits = payload["lines"]
        hits.is_a?(Array) ? (1..hits.length).to_a : []
      end

      # A changed line past the end of the report's lines array reads as
      # never-relevant and silently drops out of the denominator, which is
      # right for a fresh report and wrong for a stale one — so say which
      # is likelier out loud instead of letting a `--minimum` gate pass
      # vacuously over unscored new code.
      def warn_stale(path, payload, changed, stderr)
        hits = payload["lines"]
        return unless hits.is_a?(Array)
        return if changed.empty? || changed.max <= hits.length

        stderr.puts("simplecov patch: #{path} changed beyond the #{hits.length}-line entry in the " \
                    "report (is the report stale? regenerate it and rerun)")
      end

      def build_row(path, payload, changed)
        {
          file: path,
          line: line_stats(payload["lines"], changed),
          branch: branch_stats(payload["branches"], changed)
        }
      end

      # A line counts only where the report gives it an Integer hit count; a
      # never-relevant line (nil) or a `:nocov:` line ("ignored") stays out of
      # the denominator, the same rule the file total uses.
      def line_stats(hits, changed)
        covered = 0
        missing = [] #: Array[Integer]
        return {covered: covered, relevant: 0, missing: missing} unless hits.is_a?(Array)

        changed.each do |number|
          hit = hits[number - 1]
          # nil / "ignored" (nocov) / any non-Integer -> never relevant, skipped.
          next unless hit.is_a?(Integer)

          hit.positive? ? (covered += 1) : (missing << number)
        end
        {covered: covered, relevant: covered + missing.size, missing: missing.sort}
      end

      # nil when the report carries no branch data (branch coverage off), so
      # the output and gate skip the criterion rather than reporting a hollow
      # 0/0. A branch counts when the line it is reported on was touched;
      # "ignored" (nocov) branches drop out like nocov lines. Its miss is
      # recorded at that reported line so the note points where the source is.
      def branch_stats(branches, changed)
        return nil unless branches.is_a?(Array)

        covered = 0
        missing = [] #: Array[Integer]
        each_touched_branch(branches, changed) do |line, hits|
          hits.positive? ? (covered += 1) : (missing << line)
        end
        {covered: covered, relevant: covered + missing.size, missing: missing.uniq.sort}
      end

      # Yields [reported_line, hit_count] for each branch reported on a touched
      # line that carries a real hit count; "ignored" (nocov) branches and
      # branches off the change are skipped.
      def each_touched_branch(branches, changed)
        branches.each do |branch|
          next unless branch.is_a?(Hash)

          line = branch["report_line"] || branch["start_line"]
          hits = branch["coverage"]
          yield line, hits if changed.include?(line) && hits.is_a?(Integer)
        end
      end

      # Whether anything scored in this row: a coverable touched line, or a
      # touched branch.
      def scored?(row)
        branch = row[:branch]
        row[:line][:relevant].positive? || (branch.is_a?(Hash) && branch[:relevant].positive?)
      end
    end
  end
end
