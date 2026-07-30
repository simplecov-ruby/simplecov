# frozen_string_literal: true

module SimpleCov
  #
  # Folds a list of resultset files into one merged coverage table across
  # forked worker processes. Drives `SimpleCov.parallel_collate`.
  #
  # `ResultMerger.merge_resultsets` is a fold over N independent
  # read-parse-combine steps, so it splits cleanly: each worker runs that
  # same fold over a contiguous slice of the file list and ships the pair
  # back over a pipe, and the parent combines the handful of per-worker
  # pairs it gets back. Reading and parsing the shards — where a collate
  # over a few hundred CI jobs spends most of its time — is what actually
  # parallelises.
  #
  # The slices are contiguous and merged back in order, so the fold visits
  # the resultsets in the order the serial fold visits them and the merged
  # result is identical to `SimpleCov.collate`'s, not merely equivalent.
  #
  # Every failure path returns nil rather than a partial merge, so the caller
  # can redo the fold serially: reporting coverage for a subset of the
  # resultsets would silently understate it.
  #
  module ParallelResultMerger
  module_function

    #
    # `ResultMerger.merge_and_store` across `processes` forked workers.
    #
    def merge_and_store(*file_paths, processes:, ignore_timeout: false)
      result = merge_results(*file_paths, processes: processes, ignore_timeout: ignore_timeout)
      ResultMerger.store_result(result) if result
      result
    end

    #
    # `ResultMerger.merge_results` across `processes` forked workers, merging
    # in this process instead whenever the fan-out did not produce a complete
    # merge — a runtime that cannot fork, nothing worth splitting, or a worker
    # that died. The result is the same either way; only the time it took to
    # get there differs.
    #
    def merge_results(*file_paths, processes:, ignore_timeout: false)
      command_names, coverage =
        merge_resultsets(file_paths, processes: processes, ignore_timeout: ignore_timeout) ||
        ResultMerger.merge_resultsets(file_paths, ignore_timeout: ignore_timeout)

      ResultMerger.create_result(command_names, coverage)
    end

    #
    # `ResultMerger.merge_resultsets` across at most `processes` forked
    # workers: same arguments, same `[command_names, coverage]` return.
    #
    # @return [Array(Array<String>, Hash), nil] the pair
    #   `ResultMerger.create_result` consumes, or nil when the work could not
    #   be fanned out and the caller should merge in this process instead.
    #
    def merge_resultsets(file_paths, processes:, ignore_timeout: false)
      # One worker folds the whole list anyway, and one file is a fold of
      # one — in both cases the fork and the round trip are pure overhead.
      return nil if processes < 2 || file_paths.size < 2
      return nil unless fork_supported?

      fan_out(chunk(file_paths, processes), ignore_timeout: ignore_timeout)
    end

    def fork_supported?
      Process.respond_to?(:fork)
    end

    # Contiguous slices whose sizes differ by at most one, so no worker is
    # left folding twice its share while the others idle. There are never
    # more slices than files: asking for more processes than there are
    # resultsets just gives one resultset per process.
    def chunk(file_paths, processes)
      groups = [processes, file_paths.size].min
      base, remainder = file_paths.size.divmod(groups)
      remaining = file_paths.dup

      Array.new(groups) { |index| remaining.shift(base + (index < remainder ? 1 : 0)) }
    end

    def fan_out(chunks, ignore_timeout:)
      workers = spawn_workers(chunks, ignore_timeout: ignore_timeout)
      return nil unless workers

      payloads = collect(workers)
      payloads && ResultMerger.merge_coverage(*payloads)
    end

    # nil when this runtime turns out not to support forking after all.
    # JRuby, TruffleRuby and Windows define `Process.fork` and raise only
    # when it is called, so this — rather than the `respond_to?` probe — is
    # what actually detects them. Anything already spawned is torn down.
    def spawn_workers(chunks, ignore_timeout:)
      workers = [] #: Array[Hash[Symbol, untyped]]
      # Accumulated rather than mapped so the rescue below can still see the
      # workers spawned before the failing fork.
      chunks.each { |chunk| workers << spawn_worker(chunk, ignore_timeout: ignore_timeout) } # rubocop:disable Style/MapIntoArray
      workers
    rescue NotImplementedError
      # @type var workers: Array[Hash[Symbol, untyped]]
      shut_down(workers)
      nil
    end

    def spawn_worker(chunk, ignore_timeout:)
      reader, writer = IO.pipe

      pid = fork do
        # simplecov:disable — the child's lines are measured in the child,
        # which exits via `exit!` without reporting; `run_worker` itself is
        # covered by calling it directly.
        reader.close
        exit!(run_worker(chunk, writer, ignore_timeout: ignore_timeout))
        # simplecov:enable
      end

      writer.close
      {pid: pid, reader: reader}
    end

    # The body of a worker: fold the slice, ship it back, and report the exit
    # status the child should terminate with. Kept free of the exit itself so
    # it can be exercised in-process.
    #
    # A child must never fall through to the collating process's `at_exit`
    # handlers — SimpleCov's own report generation included — which is why
    # `spawn_worker` ends it with `exit!` rather than `exit`.
    def run_worker(chunk, writer, ignore_timeout:)
      Marshal.dump(ResultMerger.merge_resultsets(chunk, ignore_timeout: ignore_timeout), writer)
      writer.close
      0
    rescue StandardError => e
      warn "[SimpleCov]: parallel merge worker failed: #{e.class}: #{e.message}" if SimpleCov.print_errors
      1
    end

    # Deserializes on a thread per worker so every pipe is drained while the
    # workers are still writing. A payload larger than the pipe buffer would
    # otherwise block its worker mid-write, and the parent would block
    # reaping a worker that can never finish.
    #
    # Returns nil if any worker failed, so the caller can fall back to the
    # serial fold rather than report a subset of the resultsets as the whole.
    def collect(workers)
      payloads = drain(workers)
      failed = workers.count { |worker| !succeeded?(worker[:pid]) }
      return payloads if failed.zero? && payloads.all?

      warn_about_failed_workers(failed, workers.size)
      nil
    ensure
      workers.each { |worker| worker[:reader].close }
    end

    def drain(workers)
      workers.map { |worker| Thread.new { read_payload(worker[:reader]) } }.map(&:value)
    end

    def read_payload(reader)
      # The writer is a fork of this very process and the pipe never leaves
      # it, so this is our own data coming back through our own kernel
      # buffer, not input. A worker that died mid-write leaves the stream
      # truncated, which Marshal reports by raising rather than returning.
      # RBS types `Marshal.load`'s source as `_Source`, which IO satisfies
      # structurally but not nominally.
      # steep:ignore:start
      Marshal.load(reader) # rubocop:disable Security/MarshalLoad
      # steep:ignore:end
    rescue StandardError
      nil
    end

    def succeeded?(pid)
      _pid, status = Process.wait2(pid)
      status.success?
    rescue SystemCallError
      # Errno::ECHILD — nothing left to reap, so there is no status to judge
      # this worker's slice by and we have to assume it did not finish.
      false
    end

    def warn_about_failed_workers(failed, total)
      return unless SimpleCov.print_errors

      warn "[SimpleCov]: parallel merge did not complete (#{failed} of #{total} workers failed); " \
           "falling back to merging the resultsets in this process."
    end

    # Best-effort teardown for workers spawned before a fork failed. Closing
    # the read end makes a worker still writing die of EPIPE.
    def shut_down(workers)
      workers.each do |worker|
        worker[:reader].close
        succeeded?(worker[:pid])
      end
    end
  end
end
