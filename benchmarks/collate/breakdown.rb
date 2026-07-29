# frozen_string_literal: true

module CollateBenchmark
  # Opt-in attribution of the merge phase to the methods inside it, so a change
  # can be aimed rather than guessed at.
  #
  # Each wrapper adds a couple of `clock_gettime` calls per invocation, which is
  # a few percent on the merge phase — enough that an instrumented run makes a
  # poor baseline, which is why `Report` records the flag alongside the timings.
  module Breakdown
  module_function

    # Labelled as `[description, module, method]`. The modules are resolved
    # lazily because this file is loaded before `simplecov` is.
    TARGETS = [
      ["ResultsetFile.parse (read + JSON)", %w[ResultMerger ResultsetFile], :parse],
      ["LegacyFormatAdapter.call", %w[ResultMerger LegacyFormatAdapter], :call],
      ["ResultsCombiner.combine_result_sets", %w[Combine ResultsCombiner], :combine_result_sets],
      ["FilesCombiner.reconcile_synthesized", %w[Combine FilesCombiner], :reconcile_synthesized],
      ["LinesCombiner.combine", %w[Combine LinesCombiner], :combine],
      ["BranchesCombiner.combine", %w[Combine BranchesCombiner], :combine]
    ].freeze

    # `combine_result_sets` calls the three combiners, so its own row is
    # reported net of them — otherwise the shares sum to well over 100%.
    NESTED_IN_RESULTS_COMBINER = ["FilesCombiner.reconcile_synthesized", "LinesCombiner.combine",
                                  "BranchesCombiner.combine"].freeze

    Row = Struct.new(:label, :seconds, :calls, :share, keyword_init: true)

    def totals
      @totals ||= Hash.new(0.0)
    end

    def counts
      @counts ||= Hash.new(0)
    end

    def install!
      TARGETS.each { |label, path, method_name| wrap(label, path.reduce(SimpleCov, :const_get), method_name) }
    end

    def wrap(label, target, method_name)
      original = target.method(method_name)
      target.define_singleton_method(method_name) do |*args, **kwargs, &block|
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        original.call(*args, **kwargs, &block)
      ensure
        Breakdown.totals[label] += Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        Breakdown.counts[label] += 1
      end
    end

    def rows(wall)
      net_totals.sort_by { |_, seconds| -seconds }.map do |label, seconds|
        Row.new(label: label, seconds: seconds, calls: counts[label], share: seconds / wall * 100)
      end
    end

    def net_totals
      nested = totals.slice(*NESTED_IN_RESULTS_COMBINER).values.sum
      totals.to_h do |label, seconds|
        [label, label.start_with?("ResultsCombiner") ? seconds - nested : seconds]
      end
    end
  end
end
