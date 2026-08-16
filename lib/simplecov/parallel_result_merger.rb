# frozen_string_literal: true

module SimpleCov
  #
  # Folds a list of resultset files into one merged coverage table across
  # forked worker processes. Drives `SimpleCov.collate(..., processes: N)`.
  #
  # `ResultMerger.absorb_results` is a fold over N independent
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
  # rubocop:disable Metrics/ModuleLength -- one fork/pipe/reap pipeline;
  # splitting it would separate steps that only make sense together
  module ParallelResultMerger
  module_function

    #
    # `ResultMerger.merge_and_store` across `processes` forked workers. One
    # worker hands straight back to `ResultMerger`, so the default `collate`
    # takes exactly the path it always has and never reaches this module's
    # machinery at all.
    #
    def merge_and_store(*file_paths, processes:, ignore_timeout: false)
      return ResultMerger.merge_and_store(*file_paths, ignore_timeout: ignore_timeout) if processes < 2

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
      tracked_files = Set.new
      contexts = TestContexts::Union.new
      pair = absorb_results(file_paths, processes: processes, ignore_timeout: ignore_timeout,
                                        tracked_files: tracked_files, contexts: contexts)
      # A nil pair means nothing was fanned out at all, so the serial path
      # is exactly `ResultMerger.merge_results` — delegate rather than
      # re-implement its collector wiring.
      return ResultMerger.merge_results(*file_paths, ignore_timeout: ignore_timeout) unless pair

      command_names, coverage = pair
      ResultMerger.create_result(command_names, coverage, tracked_files: tracked_files,
                                                          test_contexts: contexts.result_with_drop_warning)
    end

    #
    # `ResultMerger.absorb_results` across at most `processes` forked
    # workers: same arguments, same `[command_names, coverage]` return.
    #
    # The tracked paths a worker's slice carried come back with its payload
    # rather than through a collector block, since the block a serial absorb
    # takes would be mutating a Set in the wrong process.
    #
    # @return [Array(Array<String>, Hash), nil] the pair
    #   `ResultMerger.create_result` consumes, or nil when the work could not
    #   be fanned out and the caller should merge in this process instead.
    #
    def absorb_results(file_paths, processes:, ignore_timeout: false, tracked_files: Set.new, contexts: nil)
      # One worker folds the whole list anyway, and one file is a fold of
      # one — in both cases the fork and the round trip are pure overhead.
      return nil if processes < 2 || file_paths.size < 2
      # The portable feature test, and the one the rest of the ecosystem uses.
      # CRuby leaves `fork` undefined on Windows; JRuby and TruffleRuby cannot
      # fork on the JVM and deliberately answer false here so libraries can
      # detect that without rescuing an exception — TruffleRuby's compatibility
      # guide names this as the correct check. They do still define
      # `Kernel#fork` and raise `NotImplementedError` from it, so probing that
      # instead would answer true and send them down the fan-out.
      return nil unless Process.respond_to?(:fork)

      fan_out(chunk(file_paths, processes), ignore_timeout: ignore_timeout,
                                            tracked_files: tracked_files, contexts: contexts)
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

    # A `fork` that fails here raises, and is left to. `absorb_results` has
    # already excluded the runtimes that never fork, so what remains is the OS
    # refusing a process we expected to get — EAGAIN at RLIMIT_NPROC, ENOMEM
    # under memory pressure. That says something is wrong with the machine
    # rather than with the merge, and quietly absorbing it would hide it.
    def fan_out(chunks, ignore_timeout:, tracked_files: Set.new, contexts: nil)
      workers = spawn_workers(chunks, ignore_timeout: ignore_timeout)
      payloads = collect(workers)
      return nil unless payloads

      payloads.each do |(_pair, tracked, contexts_dump)|
        tracked_files.merge(tracked)
        contexts&.absorb_dump(contexts_dump)
      end
      ResultMerger.merge_coverage(*payloads.map(&:first))
    end

    def spawn_workers(chunks, ignore_timeout:)
      workers = [] #: Array[Hash[Symbol, untyped]]

      chunks.each do |chunk|
        workers << spawn_worker(chunk, ignore_timeout: ignore_timeout)
      rescue StandardError
        abandon(workers)
        raise
      end

      workers
    end

    def abandon(workers)
      workers.each do |worker|
        worker[:reader].close
        succeeded?(worker[:pid])
      end
    end

    # `fork` itself can fail (EAGAIN under a process limit). The caller
    # cleans up the workers it knows about, but this pipe is ours: the
    # parent's writer end always closes, and the reader closes too when
    # no child was spawned to feed it. Steep cannot type body locals
    # inside an ensure, hence the ignore markers; the safe navigation
    # keeps the cleanup well-defined when `IO.pipe` itself raised.
    def spawn_worker(chunk, ignore_timeout:)
      reader, writer = IO.pipe
      pid = fork { run_in_child(reader, writer, chunk, ignore_timeout) }
      {pid: pid, reader: reader}
    ensure
      # steep:ignore:start
      writer&.close
      reader&.close unless pid
      # steep:ignore:end
    end

    # Everything the child does. `exit!` rather than `exit` because it must
    # never fall through to the collating process's inherited `at_exit`
    # handlers — SimpleCov's own report generation included.
    def run_in_child(reader, writer, chunk, ignore_timeout)
      reader.close
      exit!(run_worker(chunk, writer, ignore_timeout: ignore_timeout))
    end

    # The body of a worker: merge the slice, ship it back, and report the exit
    # status the child should terminate with. Kept free of the exit itself so
    # it can be exercised in-process.
    #
    # The slice's tracked paths travel with the pair because the parent needs
    # the union across every worker to know what nothing loaded.
    def run_worker(chunk, writer, ignore_timeout:)
      tracked_files = Set.new
      contexts = TestContexts::Union.new
      pair = ResultMerger.absorb_results(chunk, ignore_timeout: ignore_timeout,
                                         &ResultMerger::MergeCollector.call(tracked_files, contexts))
      Marshal.dump([pair, tracked_files.to_a, contexts.dump], writer)
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
           "merging the resultsets in this process instead."
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
