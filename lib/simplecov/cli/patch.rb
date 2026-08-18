# frozen_string_literal: true

require "json"
require "open3"
require "optparse"
require_relative "command_helpers"

module SimpleCov
  module CLI
    # `simplecov patch [--base REF]` — report line coverage over only the
    # lines a change touched. Where `diff` asks "did the number move" and
    # needs a baseline artifact, `patch` asks the question a reviewer
    # actually asks: is the code in this change tested? A project sitting
    # at 40% cannot move its global number in one pull request, but it can
    # insist that every line it adds is covered.
    #
    # It reads `git diff --unified=0 <base>...HEAD`, intersects the added
    # and modified line numbers with the current report (--input), and
    # prints coverage over just those lines. `--minimum N` exits non-zero
    # below a floor, so it composes as a CI gate alongside the existing
    # threshold checks, and `--json` emits rows the way the other
    # read-only commands do.
    #
    # Only files the report already carries are scored: a changed file
    # SimpleCov never tracked (a non-Ruby file, or one outside the
    # configured `cover` / `track_files` set) is out of scope, and a line
    # `LinesClassifier` considers never relevant (blank or comment) stays
    # out of the denominator the same way it stays out of the file total.
    #
    # rubocop:disable Metrics/ModuleLength -- one cohesive command: diff
    # parsing, coverage intersection, and rendering read top-to-bottom here.
    module Patch
      extend CommandHelpers

      # Below this a percentage delta is float noise; the gate compares
      # with the same tolerance row inclusion uses so a 99.999%-covered
      # patch is not failed against a --minimum of 100 by rounding.
      EPSILON = 0.005

      # The default when `--base` is omitted; overridden in CI with the
      # target branch (or its merge-base) the change is compared against.
      DEFAULT_BASE = "main"

      # A `git diff --unified=0` hunk header: `@@ -old[,cnt] +new[,cnt] @@`.
      # Only the new-file side is captured — removed lines cannot be
      # covered, so they never enter the denominator.
      HUNK_HEADER = /\A@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/

    module_function

      def run(args, stdout:, stderr:, **)
        opts = parse(args, stderr)
        return 1 unless opts

        changes = changed_lines(opts[:base], find_renames: opts[:find_renames], stderr: stderr)
        return 1 unless changes

        rows = compute_rows(opts[:coverage], changes)
        emit(stdout, rows, opts)
        gate(rows, opts[:minimum])
      end

      def parse(args, stderr)
        opts, = parse_common(args, base: DEFAULT_BASE, find_renames: false, minimum: nil) do |parser, options|
          parser.on("--base REF") { |v| options[:base] = v }
          parser.on("--minimum N", Float) { |v| options[:minimum] = v }
          parser.on("--find-renames") { options[:find_renames] = true }
        end
        opts[:coverage] = CoverageFile.load_coverage(opts[:input], command: "patch", stderr: stderr) or return nil
        opts
      end

      # --- git ----------------------------------------------------------

      # nil signals "could not diff" (already reported); an empty hash is
      # a valid result meaning the change touched no lines at all.
      def changed_lines(base, find_renames:, stderr:)
        output = git_diff(base, find_renames: find_renames)
        return report_git_error(stderr, base) unless output

        parse_diff(output)
      end

      # `...HEAD` is the three-dot range: lines HEAD added since it and
      # <base> diverged, so a base that has moved on independently does
      # not read as the change's own work. `--relative` makes the output
      # paths relative to the working directory, which is what the report
      # keys on (`project_filename`), so a run from the project root lines
      # up its paths with the report's. `--no-ext-diff` / `--no-color`
      # keep a user's git config from corrupting the machine-read output.
      # stderr is folded in and discarded so git's diagnostics for a
      # non-git tree or bad ref don't reach the build; a non-zero exit
      # (or a missing git) becomes nil, which `changed_lines` reports.
      def git_diff(base, find_renames:)
        cmd = ["git", "diff", "--unified=0", "--relative", "--no-color", "--no-ext-diff"]
        cmd << "--find-renames" if find_renames
        cmd += ["#{base}...HEAD", "--"]
        output, status = Open3.capture2e(*cmd)
        status.success? ? output : nil
      rescue StandardError
        nil # git is not installed / not on PATH
      end

      def report_git_error(stderr, base)
        stderr.puts("simplecov patch: could not run `git diff` against #{base.inspect} " \
                    "(is this a git working tree, and does the ref exist?)")
        nil
      end

      # Parse `git diff --unified=0` into {new_path => [added line numbers]}.
      # A file's added lines are read straight off its hunk headers, which
      # under --unified=0 carry no context to filter out.
      def parse_diff(output)
        changes = {} #: Hash[String, Array[Integer]]
        path = nil #: String?
        output.each_line do |line|
          if line.start_with?("+++ ")
            path = diff_path(line)
          elsif path && (match = HUNK_HEADER.match(line))
            record_hunk(changes, path, match)
          end
        end
        changes
      end

      def record_hunk(changes, path, match)
        start = match[1].to_i
        count = match[2] ? match[2].to_i : 1
        return if count.zero? # a pure-deletion hunk adds nothing

        (changes[path] ||= []).concat((start...(start + count)).to_a)
      end

      # "+++ b/lib/foo.rb" -> "lib/foo.rb"; a deleted file's "+++ /dev/null"
      # -> nil so its hunks are skipped.
      def diff_path(line)
        raw = line[4..].to_s.chomp
        # git's own literal token for an absent side, not this host's null
        # device, so File::NULL (which is "NUL" on Windows) would be wrong.
        return nil if raw == "/dev/null" # rubocop:disable Style/FileNull

        raw.sub(%r{\A[ab]/}, "")
      end

      # --- coverage intersection ---------------------------------------

      def compute_rows(coverage, changes)
        changes.filter_map do |path, lines|
          entry = CoverageFile.lookup(coverage, path)
          next unless entry.is_a?(Array) # untracked file -> out of scope

          row = build_row(path, entry.last, lines.uniq)
          row if scored?(row) # nothing coverable changed in this file
        end
      end

      def build_row(path, payload, changed)
        empty = {} #: Hash[String, untyped]
        payload = empty unless payload.is_a?(Hash)
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

      def scored?(row)
        row[:line][:relevant].positive? || branch?(row)
      end

      def branch?(row)
        row[:branch].is_a?(Hash) && row[:branch][:relevant].positive?
      end

      # --- output & gate -----------------------------------------------

      def emit(stdout, rows, opts)
        if opts[:json]
          stdout.puts(JSON.pretty_generate(json_rows(rows)))
        else
          emit_text(stdout, rows, SimpleCov::CLI.color_enabled?(opts, stdout))
        end
      end

      def emit_text(stdout, rows, color)
        return stdout.puts("simplecov patch: no coverable lines changed") if rows.empty?

        rows.sort_by! { |row| [pct(row[:line]), row[:file]] }
        rows.each { |row| stdout.puts(format_row(row, color)) }
        stdout.puts(format_total(rows, color))
      end

      def format_row(row, color)
        line = "  #{criterion_cells(row, color).join('  ')}  #{row[:file]}"
        note = missing_note(row)
        note.empty? ? line : "#{line}  #{note}"
      end

      # A "lines" cell always, a "branches" cell only when the file's touched
      # lines actually carried a branch — a hollow 0/0 branch cell is noise.
      def criterion_cells(row, color)
        cells = [criterion_cell("lines", row[:line], color)]
        cells << criterion_cell("branches", row[:branch], color) if branch?(row)
        cells
      end

      def criterion_cell(label, stats, color)
        "#{pct_cell(pct(stats), color)} (#{stats[:covered]}/#{stats[:relevant]}) #{label}"
      end

      def missing_note(row)
        parts = [] #: Array[String]
        parts << "missing #{ranges(row[:line][:missing])}" if row[:line][:missing].any?
        parts << "branch #{ranges(row[:branch][:missing])}" if branch?(row) && row[:branch][:missing].any?
        parts.join("  ")
      end

      def format_total(rows, color)
        line = sum_stats(rows, :line)
        parts = [criterion_cell("lines", line, color)]
        branch = sum_stats(rows, :branch)
        parts << criterion_cell("branches", branch, color) if branch[:relevant].positive?
        "  Patch coverage: #{parts.join(', ')}"
      end

      def json_rows(rows)
        rows.map do |row|
          data = {file: row[:file], line: row[:line].merge(percent: pct(row[:line]))}
          data[:branch] = row[:branch].merge(percent: pct(row[:branch])) if branch?(row)
          data
        end
      end

      def pct_cell(percent, color)
        text = format("%6.2f%%", percent)
        SimpleCov::Color.colorize(text, percent >= 100 ? :green : :red, enabled: color)
      end

      # Collapse a sorted line list into ranges: [41, 42, 43, 47] -> "41-43, 47".
      def ranges(numbers)
        numbers.slice_when { |prev, curr| curr > prev + 1 }
               .map { |run| run.size == 1 ? run.first.to_s : "#{run.first}-#{run.last}" }
               .join(", ")
      end

      # Sum a criterion's {covered, relevant} across rows; branch stats are nil
      # on rows from a line-only report, so those are skipped.
      def sum_stats(rows, criterion)
        stats = rows.filter_map { |row| row[criterion] }
        {covered: stats.sum { |stat| stat[:covered] }, relevant: stats.sum { |stat| stat[:relevant] }}
      end

      def pct(stats)
        relevant = stats[:relevant]
        return 100.0 if relevant.zero?

        (stats[:covered].to_f / relevant * 100).round(2)
      end

      # No --minimum is report-only (exit 0). With one, line coverage must
      # clear the floor and, when the report measured branches, so must the
      # branch coverage of the touched branches.
      def gate(rows, minimum)
        return 0 unless minimum

        line = sum_stats(rows, :line)
        branch = sum_stats(rows, :branch)
        below = pct(line) + EPSILON < minimum
        below ||= branch[:relevant].positive? && (pct(branch) + EPSILON < minimum)
        below ? 1 : 0
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
