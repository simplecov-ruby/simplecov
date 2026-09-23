# frozen_string_literal: true

require "English"

module SimpleCov
  module CLI
    module Affected
      # Starts the runner at the repository root, since the selection's paths
      # are relative to it, and answers the runner's exit status.
      module SpawnedRunner
        extend self

        def call(command, root)
          _, status = Process.wait2(spawn(*command, chdir: root))
          status.exitstatus || 1
        end
      end

      # JRuby on Windows answers Process.wait2 with a nil status and ignores
      # the chdir option Kernel#system takes, so there the runner starts
      # inside Dir.chdir, and Kernel#system reports its status.
      module SystemRunner
        extend self

        def call(command, root)
          ran = Dir.chdir(root) { system(*command) }
          raise Errno::ENOENT, command.first if ran.nil?

          $CHILD_STATUS.exitstatus || 1
        end
      end

      # simplecov:disable branch — fixed by the running engine and OS
      RUNNER = (RUBY_ENGINE.eql?("jruby") && Gem.win_platform?) ? SystemRunner : SpawnedRunner
      # simplecov:enable branch
    end
  end
end
