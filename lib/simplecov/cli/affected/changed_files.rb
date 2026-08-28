# frozen_string_literal: true

require_relative "../git"

module SimpleCov
  module CLI
    module Affected
      # The change as git sees it, returned as `{root:, changed:}`: the
      # files that differ between the merge base of the given ref and
      # HEAD and the working tree — `--merge-base` keeps commits that
      # landed on the base after the branch point out while uncommitted
      # work stays in — unioned with untracked files (a brand-new spec
      # exists in no diff). Everything runs against the repository
      # toplevel (`root`) rather than the cwd, so a subdirectory run
      # selects over the whole change. NUL separation keeps exotic
      # filenames literal instead of quoted.
      module ChangedFiles
        extend self

        # nil after reporting a git failure.
        def call(base, stderr)
          return report(stderr, "invalid base ref #{base.inspect}") if Git.option_like_ref?(base)

          root = toplevel(stderr)
          return nil unless root

          diff = list("diff", ["-C", root, "diff", "--name-only", "-z", "--merge-base", base, "--"], stderr)
          return nil unless diff

          untracked = list("ls-files", ["-C", root, "ls-files", "--others", "--exclude-standard", "-z"], stderr)
          untracked && {root: root, changed: (diff + untracked).uniq}
        end

        # nil stdout from `Git.capture` means git never ran; a run that
        # failed means the cwd is outside a working tree.
        def toplevel(stderr)
          stdout, detail, success = Git.capture("rev-parse", "--show-toplevel")
          return (_ = stdout).chomp if success
          return report(stderr, "cannot run git (#{detail})") if stdout.nil?

          report(stderr, "not inside a git working tree")
        end

        # A NUL-separated git listing, with git's own first stderr line
        # relayed on failure so a bad ref or an old git names itself.
        def list(command, argv, stderr)
          stdout, detail, success = Git.capture(*argv)
          return (_ = stdout).split("\0") if success
          return report(stderr, "cannot run git (#{detail})") if stdout.nil?

          report(stderr, "`git #{command}` failed: #{detail}")
        end

        # Answers nothing, which is what a git call that failed returns.
        def report(stderr, message)
          stderr.puts("simplecov affected: #{message}")
        end
      end
    end
  end
end
