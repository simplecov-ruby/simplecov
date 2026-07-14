# frozen_string_literal: true

# Hooks `Process._fork` (Ruby 3.1+) so child processes inherit SimpleCov's
# coverage tracking when `SimpleCov.enable_for_subprocesses?` is set.
#
# `Process._fork` is the official extension point: `Kernel#fork`,
# `Process.fork`, `IO.popen("-")`, and similar all funnel through it.
# Hooking `_fork` (instead of redefining `Process.fork`) composes
# correctly with other libraries doing the same — they each prepend
# their own module and chain via `super`.

# Reopened here for the fork-related at_exit plumbing that only matters
# when subprocess support is loaded.
module SimpleCov
  class << self
    # Forked children inherit at_exit state that is wrong for them:
    # @at_exit_hook_installed may describe a hook the parent already
    # consumed before forking (Minitest autorun runs the suite inside the
    # parent's at_exit, after SimpleCov's own hook has fired), and
    # external_at_exit may point at a Minitest.after_run deferral that is
    # pid-pinned to the parent. Reset both so the at_fork proc's
    # SimpleCov.start installs a fresh hook that actually fires at child
    # exit. See issue #1227.
    def reset_inherited_at_exit_state!
      @at_exit_hook_installed = false
      self.external_at_exit = false
    end
  end

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
        # Without this, a child forked under Minitest autorun measures
        # coverage and then silently discards it: every inherited exit
        # route is dead in the child (see the method's comment). A custom
        # at_fork runs afterwards and can still override. See issue #1227.
        SimpleCov.reset_inherited_at_exit_state!
        SimpleCov.at_fork.call(::Process.pid)
      end
      pid
    end
  end
end

Process.singleton_class.prepend(SimpleCov::ProcessForkHook)
