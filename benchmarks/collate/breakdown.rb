# frozen_string_literal: true

module CollateBenchmark
  # Opt-in attribution of the merge phase to the methods inside it, so a change
  # can be aimed rather than guessed at.
  #
  # Each wrapper adds a couple of `clock_gettime` calls per invocation, which is
  # a few percent on the merge phase — enough that an instrumented run makes a
  # poor baseline, which is why `Report` records the flag alongside the timings.
  module Breakdown
    extend self

    # Labelled as `[description, module, method]`. The modules are resolved
    # lazily because this file is loaded before `simplecov` is.
    TARGETS = [
      ["ResultsetFile.parse (read + JSON)", %w[ResultMerger ResultsetFile], :parse],
      ["LegacyFormatAdapter.call", %w[ResultMerger LegacyFormatAdapter], :call],
      ["LinesCombiner.merge_into", %w[Combine LinesCombiner], :merge_into],
      ["BranchesCombiner.absorb", %w[Combine BranchesCombiner], :absorb],
      ["BranchesCombiner.materialize", %w[Combine BranchesCombiner], :materialize],
      ["MethodsCombiner.absorb", %w[Combine MethodsCombiner], :absorb]
    ].freeze

    # Same, for the instance methods that drive those combiners.
    INSTANCE_TARGETS = [
      ["CoverageAccumulator#absorb", %w[Combine CoverageAccumulator], :absorb],
      ["CoverageAccumulator#result", %w[Combine CoverageAccumulator], :result]
    ].freeze

    # A caller's own row is reported net of the callees listed here —
    # otherwise the shares sum to well over 100%.
    NESTED = {
      "CoverageAccumulator#absorb" => ["LinesCombiner.merge_into", "BranchesCombiner.absorb",
                                       "MethodsCombiner.absorb"],
      "CoverageAccumulator#result" => ["BranchesCombiner.materialize"]
    }.freeze

    Row = Struct.new(:label, :seconds, :calls, :share, keyword_init: true)

    def totals
      @totals ||= Hash.new(0.0)
    end

    def counts
      @counts ||= Hash.new(0)
    end

    def install!
      TARGETS.each { |label, path, method_name| wrap(label, path.reduce(SimpleCov, :const_get), method_name) }
      INSTANCE_TARGETS.each do |label, path, method_name|
        wrap_instance(label, path.reduce(SimpleCov, :const_get), method_name)
      end
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

    # Instance methods can't be redefined on the singleton, so time them from
    # a prepended module instead.
    def wrap_instance(label, klass, method_name)
      klass.prepend(Module.new do
        define_method(method_name) do |*args, **kwargs, &block|
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          super(*args, **kwargs, &block)
        ensure
          Breakdown.totals[label] += Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
          Breakdown.counts[label] += 1
        end
      end)
    end

    def rows(wall)
      net_totals.sort_by { |_, seconds| -seconds }.map do |label, seconds|
        Row.new(label: label, seconds: seconds, calls: counts[label], share: seconds / wall * 100)
      end
    end

    def net_totals
      totals.to_h do |label, seconds|
        [label, seconds - totals.slice(*NESTED.fetch(label, [])).values.sum]
      end
    end
  end
end
