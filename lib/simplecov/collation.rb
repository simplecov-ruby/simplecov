# frozen_string_literal: true

# The `collate` entry points: stitch the resultsets written by separate
# test runs — parallel CI jobs, several build machines, a matrix of Ruby
# versions — into one report, either in this process or fanned out across
# forked workers.
module SimpleCov
  class << self
    #
    # Collate a series of SimpleCov result files into a single SimpleCov output.
    #
    # See README for usage. By default `collate` ignores the merge_timeout
    # so all results in all files specified will be merged. Pass
    # `ignore_timeout: false` to honor it.
    #
    def collate(result_filenames, profile = nil, ignore_timeout: true, &config)
      collating(result_filenames, profile, config) do
        # Use the ResultMerger to produce a single, merged result, ready to use.
        ResultMerger.merge_and_store(*result_filenames, ignore_timeout: ignore_timeout)
      end
    end

    #
    # `collate`, with the merge fanned out across `processes` forked worker
    # processes. Takes the same arguments and produces the same report: the
    # workers fold contiguous slices of `result_filenames` in the order the
    # serial merge visits them, so the merged result is identical, not merely
    # equivalent. Only the wall clock differs, and only for a collate big
    # enough that reading and parsing the resultsets dominates it.
    #
    # `processes` is required, and is deliberately not clamped to the machine's
    # core count nor gated on some minimum number of resultsets: how many
    # processes a collate job can afford is the caller's call, not SimpleCov's.
    # Asking for more processes than there are result files simply gives one
    # file per process. A `processes` below 1 raises rather than quietly
    # merging serially, so compute it with `[n, 1].max` if it comes from
    # arithmetic that can reach zero.
    #
    # Falls back to merging in this process — same report, no error — when the
    # runtime cannot fork (JRuby, TruffleRuby, Windows), when there is nothing
    # worth splitting, or when a worker dies.
    #
    def parallel_collate(result_filenames, profile = nil, processes:, ignore_timeout: true, &config)
      raise ArgumentError, "processes must be at least 1, got #{processes}" if processes < 1

      collating(result_filenames, profile, config) do
        ParallelResultMerger.merge_and_store(*result_filenames, processes: processes, ignore_timeout: ignore_timeout)
      end
    end

  private

    # The scaffolding both entry points share: validate, apply the caller's
    # profile and configuration block, then run the finalizer over whatever
    # merged result the given strategy produced. `config` is the caller's
    # configuration block, passed as an object because the merge strategy
    # occupies the block slot.
    def collating(result_filenames, profile, config)
      raise ArgumentError, "There are no reports to be merged" if result_filenames.empty?

      initial_setup(profile, &config)
      @result = yield
      @collating_result = true
      run_exit_tasks!
    ensure
      @collating_result = false
    end
  end
end
