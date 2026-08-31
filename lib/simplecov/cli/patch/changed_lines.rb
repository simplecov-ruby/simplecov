# frozen_string_literal: true

require_relative "../git"

module SimpleCov
  module CLI
    module Patch
      # Run `git diff --unified=0` against a base and parse the result into
      # `{root:, changes: {path => [added line numbers] | :all}}`, where
      # `root` is the repository toplevel the paths are relative to and
      # `:all` marks an untracked file, whose every line is new.
      module ChangedLines
        # A `git diff --unified=0` hunk header. Only the new-file side is
        # captured: removed lines cannot be covered.
        HUNK_HEADER = /\A@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/

        UNQUOTE = {
          "\\" => "\\", '"' => '"', "n" => "\n", "t" => "\t", "r" => "\r",
          "a" => "\a", "b" => "\b", "f" => "\f", "v" => "\v"
        }.freeze

        extend self

        # nil signals "could not diff" (already reported); empty changes are a
        # valid result meaning the change touched no lines at all. Everything
        # runs against the repository toplevel rather than the cwd, because
        # `--relative` from a subdirectory would exclude every change outside
        # that subdirectory from a `--minimum` gate.
        def call(base, find_renames:, stderr:)
          root = git_toplevel
          return report_git_error(stderr, base, nil) unless root

          output, detail = git_diff(root, base, find_renames: find_renames)
          return report_git_error(stderr, base, detail) unless output

          # `scrub` keeps a non-UTF-8 content line from blowing up the regexp
          # parse; hunk headers are pure ASCII.
          changes = parse_diff(output.scrub) #: Hash[String, untyped]
          untracked_files(root).each { |path| changes[path] = :all }
          {root: root, changes: changes}
        end

        def git_toplevel
          Git.toplevel
        end

        # `--merge-base <base>` diffs the merge base of <base> and the working
        # tree against the working tree: the change reads as its own work even
        # when <base> has moved on independently, and uncommitted edits count
        # too. The rest pins the output against a user's git config so it can't
        # skew the numbers, run code, or throw off the parse: `--no-ext-diff` /
        # `--no-textconv` (either runs a configured command, and the latter also
        # renumbers lines), `--no-color`, `core.quotePath=false` (emit non-ASCII
        # paths literally, so they still match report keys),
        # `--inter-hunk-context=0` (never merge hunks over unchanged lines,
        # which would score those lines as touched), fixed `a/`/`b/` prefixes
        # (so the `diff_path` strip can't be fooled by `diff.noprefix`), and
        # `--no-renames` unless asked (so a moved file reads as all-new).
        # stderr is kept out of the parsed stream and its first line returned as
        # the failure detail, so "unknown revision" reaches the user.
        def git_diff(root, base, find_renames:)
          # Refusing an option-like ref keeps a `--base` value from being read by
          # git as an option instead of a revision (`--output=FILE` writes to
          # disk, `--line-prefix=` empties the diff so a `--minimum` gate passes).
          return [nil, "a ref cannot begin with \"-\""] if Git.option_like_ref?(base)

          argv = ["-C", root, "-c", "core.quotePath=false", "diff", "--unified=0",
                  "--no-color", "--no-ext-diff", "--no-textconv", "--inter-hunk-context=0",
                  "--dst-prefix=b/",
                  find_renames ? "--find-renames" : "--no-renames", "--merge-base", base, "--"]
          stdout, detail, success = Git.capture(*argv)
          [(stdout if success), detail]
        end

        # A brand-new file that was never `git add`ed appears in no diff, but its
        # lines are this change's lines all the same, and skipping it would pass
        # a `--minimum` gate over entirely unscored new code. A failure here
        # contributes nothing rather than failing the run.
        def untracked_files(root)
          stdout, _detail, success = Git.capture("-C", root, "ls-files", "--others", "--exclude-standard", "-z")
          success ? (_ = stdout).scrub.split("\0") : []
        end

        def report_git_error(stderr, base, detail)
          reason = detail.to_s.empty? ? "is this a git working tree, and does the ref exist?" : detail
          stderr.puts("simplecov patch: could not run `git diff` against #{base.inspect} (#{reason})")
        end

        # Split into per-file sections first so a file's `+++` header, its first,
        # before any hunk, is what names the path. Inside a hunk an added line is
        # itself `+`-prefixed, so a touched line whose own text begins with
        # `++ ` renders as `+++ ...`; reading only the section's first `+++`
        # keeps that content line from standing in as the header.
        def parse_diff(output)
          changes = {} #: Hash[String, Array[Integer]]
          sections = output.split(/^(?=diff --git )/)
          sections.each do |section|
            path = section_path(section) or next
            section.each_line do |line|
              match = HUNK_HEADER.match(line)
              record_hunk(changes, path, match) if match
            end
          end
          changes
        end

        # `+++ /dev/null` (a deletion) yields nil.
        def section_path(section)
          header = section[/^\+\+\+ .+/]
          header && diff_path(header)
        end

        def record_hunk(changes, path, match)
          start = Integer(match[1])
          count = match[2] ? Integer(match[2]) : 1
          return if count.zero? # a pure-deletion hunk adds nothing

          (changes[path] ||= []).concat((start...(start + count)).to_a)
        end

        def diff_path(line)
          raw = unquote(line[4..].to_s.chomp)
          # git's own literal token for an absent side, not this host's null
          # device, so File::NULL (which is "NUL" on Windows) would be wrong.
          return nil if raw.eql?("/dev/null") # rubocop:disable Style/FileNull

          raw.sub(%r{\A[ab]/}, "")
        end

        # A path carrying a quote, backslash, or control character is emitted as
        # `"b/lib/we\"ird.rb"` even under `core.quotePath=false` (which only
        # covers non-ASCII), and left quoted it matches no coverage key.
        def unquote(raw)
          return raw unless raw.length >= 2 && raw.start_with?('"') && raw.end_with?('"')

          # Unescaped as raw bytes: an octal escape is a bare byte, and mixing one
          # into a UTF-8 string would raise mid-gsub.
          unquoted = (_ = raw.b[1..-2]).gsub(/\\(?:[0-7]{1,3}|.)/) { |escape| unescape(escape) }
          unquoted.force_encoding(raw.encoding).scrub
        end

        def unescape(escape)
          body = _ = escape[1..]
          body.match?(/\A[0-7]/) ? Integer(body, 8).chr : UNQUOTE.fetch(body, body)
        end
      end
    end
  end
end
