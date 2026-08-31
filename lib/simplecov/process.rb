# frozen_string_literal: true

module SimpleCov
  class << self
    # Forked children inherit at_exit state that is wrong for them:
    # @at_exit_hook_installed may describe a hook the parent already consumed
    # before forking (Minitest autorun runs the suite inside the parent's
    # at_exit), and external_at_exit may point at a Minitest.after_run deferral
    # that is pid-pinned to the parent. Resetting both is what lets the at_fork
    # proc's `SimpleCov.start` install a hook that actually fires (#1227).
    def reset_inherited_at_exit_state!
      @at_exit_hook_installed = false
      self.external_at_exit = false
    end
  end

  # Prepended onto Process's singleton class so every fork re-runs SimpleCov's
  # at_fork callback in the child. `Process._fork` is the official extension
  # point: `Kernel#fork`, `Process.fork`, and `IO.popen("-")` all funnel
  # through it, and prepending composes with other libraries doing the same.
  module ProcessForkHook
    # The next serial is assigned in the parent, before the fork, so the child
    # inherits its own stable ordinal via copy-on-write, and the child is marked
    # here independent of whatever custom at_fork block the user installed so
    # `final_result_process?` can keep forked workers from each producing the
    # final report (#1171, #1227).
    def _fork
      active = defined?(SimpleCov) && Coverage.running?
      SimpleCov.next_subprocess_serial! if active
      pid = super
      if pid.zero? && active
        SimpleCov.mark_forked_subprocess!
        SimpleCov.reset_inherited_at_exit_state!
        SimpleCov.at_fork.call(::Process.pid)
      end
      pid
    end
  end
end

Process.singleton_class.prepend(SimpleCov::ProcessForkHook)
