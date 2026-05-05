# frozen_string_literal: true

# Patches `Process.fork` so child processes inherit SimpleCov's coverage
# tracking when `SimpleCov.enable_for_subprocesses?` is set.
module Process
  class << self
    def fork_with_simplecov(&block)
      if defined?(SimpleCov) && SimpleCov.running
        fork_without_simplecov do
          SimpleCov.at_fork.call(Process.pid)
          yield if block
        end
      else
        fork_without_simplecov(&block)
      end
    end

    alias fork_without_simplecov fork
    alias fork fork_with_simplecov
  end
end
