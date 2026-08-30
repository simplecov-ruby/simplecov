# frozen_string_literal: true

module SimpleCov
  # The state one measured run accumulates in one process: the pid and
  # start time that identify it, the result it computes, the flags the
  # merge coordination reads, and the serial the parent hands each
  # forked subprocess. A new run is a new object, which is what lets
  # anything needing a clean slate begin one instead of unsetting
  # state on the singleton by hand.
  class CurrentRun
    attr_accessor :pid, :process_start_time, :result
    attr_writer :collating_result

    # The run that follows this one in the same process. The result,
    # the coordination flags and the identity belong to the run that
    # ends; the fork genealogy — the mark a forked child carries and
    # the serial its parent counts — belongs to the process, and
    # carries over. A child that restarts tracking must not forget it
    # was forked, or it would produce the final report itself, and a
    # parent must not recount from zero, or its next children's names
    # would collide with its first ones. See issue #1171.
    def successor
      following = self.class.new
      following.subprocess_serial = @subprocess_serial
      following.mark_forked_subprocess! if forked_subprocess?
      following
    end

    # Returns nil if the result has not been computed, otherwise the result.
    # Answers exactly false while no result was ever stored, which is
    # how "never computed" stays distinct from "cleared to nil".
    # The cast restores what `defined?` used to narrow for steep: asking
    # the object whether it holds the variable tells the checker nothing
    # about what is in it.
    def result?
      instance_variable_defined?(:@result) && (_ = @result)
    end

    # @api private — true while `SimpleCov.collate` is running its finalizer.
    def collating_result?
      !!@collating_result
    end

    # @api private — true in a process that was forked while coverage
    # was running (marked by SimpleCov::ProcessForkHook in the child).
    # Reading a mark that was never set answers nil, which is the
    # answer wanted, and no Ruby this gem supports warns about it.
    def forked_subprocess?
      !!@forked_subprocess
    end

    # @api private — marked in the child immediately after a fork.
    def mark_forked_subprocess!
      @forked_subprocess = true
    end

    # A monotonically increasing serial the parent assigns to each forked
    # subprocess (see SimpleCov::ProcessForkHook). The default `at_fork`
    # builds the worker's command_name from this rather than the OS pid:
    # the serial sequence is the same from one run to the next, so a re-run
    # overwrites the previous run's resultset entries instead of writing
    # uniquely-named ones that pile up until merge_timeout. See issue #1171.
    def subprocess_serial
      @subprocess_serial ||= 0
    end

    # @api private — bump the serial in the parent before a fork so the
    # child inherits its own ordinal via copy-on-write.
    def next_subprocess_serial!
      @subprocess_serial = subprocess_serial + 1
    end

  protected

    # Written only by `successor`, carrying the count across runs.
    attr_writer :subprocess_serial
  end
end
