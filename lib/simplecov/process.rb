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
      pid = super
      SimpleCov.at_fork.call(::Process.pid) if pid.zero? && defined?(SimpleCov) && SimpleCov.running
      pid
    end
  end
end

Process.singleton_class.prepend(SimpleCov::ProcessForkHook)
