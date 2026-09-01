# frozen_string_literal: true

require_relative "parallel_result_merger/worker_payload"

module SimpleCov
  #
  # `ResultMerger.absorb_results` fanned out across forked workers, driving
  # `SimpleCov.collate(..., processes: N)`. Each worker folds a contiguous
  # slice of the file list and ships the pair back over a pipe.
  #
  # The slices are contiguous and merged back in order, so the fold visits the
  # resultsets in the order the serial fold visits them and the merged result
  # is identical to `SimpleCov.collate`'s, not merely equivalent.
  #
  module ParallelResultMerger
    extend self

    def merge_and_store(*file_paths, processes:, ignore_timeout: false)
      return ResultMerger.merge_and_store(*file_paths, ignore_timeout: ignore_timeout) if processes < 2

      result = merge_results(*file_paths, processes: processes, ignore_timeout: ignore_timeout)
      ResultMerger.store_result(result) if result
      result
    end

    def merge_results(*file_paths, processes:, ignore_timeout: false)
      tracked_files = Set.new
      context_maps = ContextMap::Union.new
      pair = absorb_results(file_paths, processes: processes, ignore_timeout: ignore_timeout,
        tracked_files: tracked_files, context_maps: context_maps)
      return ResultMerger.merge_results(*file_paths, ignore_timeout: ignore_timeout) unless pair

      command_names, coverage = pair
      ResultMerger.create_result(command_names, coverage, tracked_files: tracked_files, contexts: context_maps.map)
    end

    # Answers nil when the work could not be fanned out and the caller should
    # merge in this process instead. The tracked paths and context-map union a
    # worker's slice carried come back with its payload rather than through a
    # collector block, since that block would be mutating state in the wrong
    # process.
    def absorb_results(file_paths, processes:, ignore_timeout: false, tracked_files: Set.new,
      context_maps: ContextMap::Union.new)
      return nil if processes < 2 || file_paths.size < 2
      # JRuby cannot fork on the JVM and deliberately answers false here, but
      # still defines `Kernel#fork` and raises `NotImplementedError` from it,
      # so probing that instead would send it down the fan-out.
      return nil unless Process.respond_to?(:fork)

      fan_out(chunk(file_paths, processes), ignore_timeout: ignore_timeout, tracked_files: tracked_files,
        context_maps: context_maps)
    end

    def chunk(file_paths, processes)
      groups = [processes, file_paths.size].min
      base, remainder = file_paths.size.divmod(groups)
      remaining = file_paths.dup

      Array.new(groups) { |index| remaining.shift(base + ((index < remainder) ? 1 : 0)) }
    end

    # A `fork` that fails here raises, and is left to: the runtimes that never
    # fork are already excluded, so what remains is the OS refusing a process
    # we expected to get, which says something is wrong with the machine rather
    # than with the merge.
    def fan_out(chunks, ignore_timeout:, tracked_files:, context_maps:)
      workers = spawn_workers(chunks, ignore_timeout: ignore_timeout)
      payloads = collect_payloads(workers)
      return nil unless payloads

      payloads.each { |payload| WorkerPayload.absorb(payload, tracked_files, context_maps) }
      ResultMerger.merge_coverage(*payloads.map { |payload| WorkerPayload.pair(payload) })
    end

    def spawn_workers(chunks, ignore_timeout:)
      workers = [] #: Array[Hash[Symbol, untyped]]
      chunks.each do |chunk|
        workers << spawn_worker(chunk, ignore_timeout: ignore_timeout)
      rescue
        abandon(workers)
        raise
      end
      workers
    end

    def abandon(workers)
      workers.each do |worker|
        worker.fetch(:reader).close
        succeeded?(worker.fetch(:pid))
      end
    end

    # The caller cleans up the workers it knows about, but this pipe is ours.
    # The safe navigation keeps the cleanup well-defined when `IO.pipe` itself
    # raised, and Steep cannot type body locals inside an ensure.
    def spawn_worker(chunk, ignore_timeout:)
      reader, writer = IO.pipe
      pid = fork { run_in_child(reader, writer, chunk, ignore_timeout) }
      {pid: pid, reader: reader}
    ensure
      # @type var writer: IO?
      # @type var reader: IO?
      # @type var pid: Integer?
      writer&.close
      reader&.close unless pid
    end

    # `exit!` rather than `exit` because the child must never fall through to
    # the collating process's inherited `at_exit` handlers, SimpleCov's own
    # report generation included.
    def run_in_child(reader, writer, chunk, ignore_timeout)
      reader.close
      exit!(run_worker(chunk, writer, ignore_timeout: ignore_timeout))
    end

    # Kept free of the exit itself so it can be exercised in-process.
    def run_worker(chunk, writer, ignore_timeout:)
      Marshal.dump(WorkerPayload.build(chunk, ignore_timeout: ignore_timeout), writer)
      writer.close
      0
    rescue => e
      warn "[SimpleCov]: parallel merge worker failed: #{e.class}: #{e}" if SimpleCov.print_errors
      1
    end

    # Answers nil if any worker failed, so the caller redoes the fold serially
    # rather than report a subset of the resultsets as the whole.
    def collect_payloads(workers)
      payloads = drain(workers)
      failed = workers.count { |worker| !succeeded?(worker.fetch(:pid)) }
      return warn_about_failed_workers(failed, workers.size) unless failed.zero? && payloads.all?

      payloads
    ensure
      workers.each { |worker| worker.fetch(:reader).close }
    end

    # A thread per worker, so every pipe is drained while the workers are still
    # writing. A payload larger than the pipe buffer would otherwise block its
    # worker mid-write, and the parent would block reaping a worker that can
    # never finish.
    def drain(workers)
      workers.map { |worker| Thread.new { read_payload(worker.fetch(:reader)) } }.map(&:value)
    end

    def read_payload(reader)
      # The writer is a fork of this very process and the pipe never leaves it,
      # so this is our own data coming back through our own kernel buffer, not
      # input.
      Marshal.load(reader) # rubocop:disable Security/MarshalLoad
    rescue
      nil
    end

    def succeeded?(pid)
      _pid, status = Process.wait2(pid)
      status.success?
    rescue SystemCallError
      # Errno::ECHILD: nothing left to reap, so there is no status to judge
      # this worker's slice by and we have to assume it did not finish.
      false
    end

    def warn_about_failed_workers(failed, total)
      return unless SimpleCov.print_errors

      warn "[SimpleCov]: parallel merge did not complete (#{failed} of #{total} workers failed); " \
           "merging the resultsets in this process instead."
    end
  end
end
