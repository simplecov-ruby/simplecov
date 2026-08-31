# frozen_string_literal: true

module SimpleCov
  # The state one measured run accumulates in one process: the pid and start
  # time that identify it, the result it computes, the flags the merge
  # coordination reads, and the serial the parent hands each forked
  # subprocess. A new run is a new object, which is what lets anything needing
  # a clean slate begin one instead of unsetting state by hand.
  class CurrentRun
    attr_accessor :pid, :process_start_time, :result
    attr_writer :collating_result

    # The result, the coordination flags and the identity belong to the run that
    # ends; the fork genealogy belongs to the process and carries over. A child
    # that restarts tracking must not forget it was forked, or it would produce
    # the final report itself, and a parent must not recount from zero, or its
    # next children's names would collide with its first ones (#1171).
    def successor
      following = self.class.new
      following.subprocess_serial = @subprocess_serial
      following.mark_forked_subprocess! if forked_subprocess?
      following
    end

    # Answers exactly false while no result was ever stored, which is how "never
    # computed" stays distinct from "cleared to nil".
    def result?
      instance_variable_defined?(:@result) && (_ = @result)
    end

    def collating_result?
      !!@collating_result
    end

    # Reading a mark that was never set answers nil, which is the answer wanted.
    def forked_subprocess?
      !!@forked_subprocess
    end

    def mark_forked_subprocess!
      @forked_subprocess = true
    end

    # A monotonically increasing serial the parent assigns to each forked
    # subprocess. The default `at_fork` builds the worker's command_name from
    # this rather than the OS pid: the serial sequence is the same from one run
    # to the next, so a re-run overwrites the previous run's resultset entries
    # instead of writing uniquely-named ones that pile up (#1171).
    def subprocess_serial
      @subprocess_serial ||= 0
    end

    def next_subprocess_serial!
      @subprocess_serial = subprocess_serial + 1
    end

  protected

    attr_writer :subprocess_serial
  end
end
