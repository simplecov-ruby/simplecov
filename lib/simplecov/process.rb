# frozen_string_literal: true

# Hooks `Process._fork` (Ruby 3.1+) so child processes inherit SimpleCov's
# coverage tracking when `SimpleCov.enable_for_subprocesses?` is set.
#
# `Process._fork` is the official extension point: `Kernel#fork`,
# `Process.fork`, `IO.popen("-")`, and similar all funnel through it.
# Hooking `_fork` (instead of redefining `Process.fork`) composes
# correctly with other libraries doing the same — they each prepend
# their own module and chain via `super`.

module SimpleCov
  # Prepended onto Process's singleton class so every fork — direct or
  # via Kernel#fork / IO.popen — re-runs SimpleCov's at_fork callback in
  # the child.
  module ProcessForkHook
    def _fork
      active = defined?(SimpleCov) && Coverage.running?
      # Assign the next serial in the PARENT, before the fork, so the child
      # inherits its own stable ordinal via copy-on-write. The default
      # at_fork uses it (instead of the child pid) to name the subprocess's
      # result, keeping that name identical across runs. See issue #1171.
      SimpleCov.next_subprocess_serial! if active
      pid = super
      if pid.zero? && active
        # Mark the child here, independent of whatever custom at_fork block
        # the user installed, so `final_result_process?` can keep forked
        # workers from each producing the final report. See issue #1171.
        SimpleCov.mark_forked_subprocess!
        SimpleCov.at_fork.call(::Process.pid)
      end
      pid
    end
  end
end

Process.singleton_class.prepend(SimpleCov::ProcessForkHook)
