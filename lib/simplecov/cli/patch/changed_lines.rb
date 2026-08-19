# frozen_string_literal: true

require "open3"

module SimpleCov
  module CLI
    module Patch
      # Run `git diff --unified=0` against a base and parse the result into
      # {new_path => [added line numbers]}.
      module ChangedLines
        # A `git diff --unified=0` hunk header: `@@ -old[,cnt] +new[,cnt] @@`.
        # Only the new-file side is captured — removed lines cannot be
        # covered, so they never enter the denominator.
        HUNK_HEADER = /\A@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/

      module_function

        # nil signals "could not diff" (already reported); an empty hash is
        # a valid result meaning the change touched no lines at all.
        def call(base, find_renames:, stderr:)
          output = git_diff(base, find_renames: find_renames)
          return report_git_error(stderr, base) unless output

          parse_diff(output)
        end

        # `--merge-base <base>` diffs the merge base of <base> and the
        # working tree against the working tree: the change reads as its
        # own work even when <base> has moved on independently, and
        # uncommitted edits count too, so `simplecov patch` run before a
        # commit still scores the lines just written. In CI, where the tree
        # is a clean checkout of HEAD, this is exactly the merge-base-to-HEAD
        # range. `--relative` makes the output paths relative to the working
        # directory, which is what the report keys on (`project_filename`),
        # so a run from the project root lines up its paths with the
        # report's. The rest pins the output against a user's git config so
        # it can't skew the numbers, run code, or throw off the parse:
        # `--no-ext-diff` / `--no-textconv` (no external diff or textconv
        # driver — either runs a configured command and the latter also
        # renumbers lines), `--no-color` (no ANSI), `core.quotePath=false`
        # (emit non-ASCII paths literally, so they still match report keys),
        # `--inter-hunk-context=0` (never merge hunks over unchanged lines,
        # which would score those lines as touched), fixed `a/`/`b/` prefixes
        # (so the `diff_path` strip can't be fooled by `diff.noprefix` /
        # `diff.*Prefix`), and `--no-renames` unless asked (so a moved file
        # reads as all-new — git detects renames by default, which
        # `--find-renames` would otherwise leave unchanged). stdout alone is
        # parsed; stderr is captured separately and dropped so git's
        # diagnostics for a non-git tree or bad ref can't reach the parser. A
        # non-zero exit (or a missing git) becomes nil, which `call` reports.
        def git_diff(base, find_renames:)
          # A git ref can never begin with "-", so refusing one keeps a
          # `--base` value from being read by git as an option instead of a
          # revision (e.g. `--output=FILE` writes to disk, `--line-prefix=`
          # empties the diff so a `--minimum` gate passes over the change).
          return nil if base.start_with?("-")

          cmd = ["git", "-c", "core.quotePath=false", "diff", "--unified=0", "--relative",
                 "--no-color", "--no-ext-diff", "--no-textconv", "--inter-hunk-context=0",
                 "--src-prefix=a/", "--dst-prefix=b/"]
          cmd += [find_renames ? "--find-renames" : "--no-renames", "--merge-base", base, "--"]
          stdout, _stderr, status = Open3.capture3(*cmd)
          status.success? ? stdout : nil
        rescue StandardError
          nil # git is not installed / not on PATH
        end

        def report_git_error(stderr, base)
          stderr.puts("simplecov patch: could not run `git diff` against #{base.inspect} " \
                      "(is this a git working tree, and does the ref exist?)")
          nil
        end

        # Parse `git diff --unified=0` into {new_path => [added line numbers]}.
        # Split into per-file sections first so a file's `+++` header — its
        # first, before any hunk — is what names the path. Inside a hunk an
        # added line is itself `+`-prefixed, so a touched line whose own text
        # begins with `++ ` renders as `+++ ...`; reading only the section's
        # first `+++` keeps that content line from standing in as the header
        # and misdirecting the rest of the file's hunks.
        def parse_diff(output)
          changes = {} #: Hash[String, Array[Integer]]
          output.split(/^(?=diff --git )/).each do |section|
            path = section_path(section) or next
            section.each_line do |line|
              match = HUNK_HEADER.match(line)
              record_hunk(changes, path, match) if match
            end
          end
          changes
        end

        # The new-file path from a diff section: its first `+++` line, which
        # precedes the first hunk. `+++ /dev/null` (a deletion) yields nil.
        def section_path(section)
          header = section[/^\+\+\+ .*/]
          header && diff_path(header)
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
      end
    end
  end
end
