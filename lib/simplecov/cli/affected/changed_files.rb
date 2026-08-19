# frozen_string_literal: true

require "open3"

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
      module_function

        # nil after reporting a git failure.
        def call(base, stderr)
          # A git ref can never begin with "-", so refusing one keeps a
          # `--base` value from being read by git as an option instead
          # of a revision.
          return report(stderr, "invalid base ref #{base.inspect}") if base.start_with?("-")

          root = toplevel(stderr)
          return nil unless root

          diff = list("diff", ["-C", root, "diff", "--name-only", "-z", "--merge-base", base, "--"], stderr)
          return nil unless diff

          untracked = list("ls-files", ["-C", root, "ls-files", "--others", "--exclude-standard", "-z"], stderr)
          untracked && {root: root, changed: (diff + untracked).uniq}
        end

        def toplevel(stderr)
          output, _error_output, status = Open3.capture3("git", "rev-parse", "--show-toplevel")
          return output.chomp if status.success?

          report(stderr, "not inside a git working tree")
        rescue SystemCallError => e
          report(stderr, "cannot run git (#{e.message})")
        end

        # A NUL-separated git listing, with git's own first stderr line
        # relayed on failure so a bad ref or an old git names itself.
        def list(command, argv, stderr)
          output, error_output, status = Open3.capture3("git", *argv)
          return output.split("\0") if status.success?

          report(stderr, "`git #{command}` failed: #{error_output.lines.first.to_s.strip}")
        rescue SystemCallError => e
          report(stderr, "cannot run git (#{e.message})")
        end

        def report(stderr, message)
          stderr.puts("simplecov affected: #{message}")
          nil
        end
      end
    end
  end
end
