# frozen_string_literal: true

require "open3"

module SimpleCov
  module CLI
    # The git plumbing the change-aware subcommands share: safe capture, the
    # repository toplevel, ref hygiene, and the default base ref.
    module Git
      extend self

      # [stdout, first stderr line, success]. A spawn failure reads as an
      # unsuccessful run whose stdout is nil, so callers can tell "git ran and
      # refused" from "git never ran".
      def capture(*argv)
        stdout, stderr, status = Open3.capture3("git", *argv)
        [stdout, stderr.lines.first.to_s.strip, status.success?]
      rescue => e
        [nil, e.message, false]
      end

      def toplevel
        stdout, _detail, success = capture("rev-parse", "--show-toplevel")
        (_ = stdout).chomp if success
      end

      # A git ref can never begin with "-", so one that does would be read by git
      # as an option instead of a revision.
      def option_like_ref?(ref)
        ref.start_with?("-")
      end

      # The branch origin's HEAD points at, so master and trunk repositories work
      # bare, falling back to main where no origin HEAD is recorded.
      def default_base
        stdout, _detail, success = capture("symbolic-ref", "--short", "refs/remotes/origin/HEAD")
        success ? (_ = stdout).chomp.delete_prefix("origin/") : "main"
      end
    end
  end
end
