# frozen_string_literal: true

require_relative "shape"
require_relative "runner"

module CollateBenchmark
  # Turns `ARGV` and the environment into a `Runner`. See benchmarks/collate.rb
  # for the documented set of knobs.
  module CLI
    DEFAULT_SCALE = 4

    DEFAULT_PROCESSES = 1

    # `resultsets` rather than `count`, which would shadow `Struct#count`.
    Options = Struct.new(:label, :resultsets, :scale, :skip, :rebuild, :baseline, :breakdown, :processes,
                         keyword_init: true)

    class << self
      def run(argv)
        Runner.new(options(argv)).call
      end

      def options(argv)
        argv = argv.dup
        Options.new(
          label: label(argv), baseline: flag_value(argv, "--baseline"),
          resultsets: ENV.fetch("COUNT", Shape::RESULTSETS).to_i,
          scale: ENV.fetch("SCALE", DEFAULT_SCALE).to_i,
          skip: skip, rebuild: ENV["REBUILD"] == "1",
          breakdown: ENV["BREAKDOWN"] == "1", processes: processes
        )
      end

      # Above 1, the merge phase runs the fan-out `SimpleCov.parallel_collate`
      # runs instead of the serial fold. Every later phase is unchanged, so a
      # PROCESSES run is directly comparable to a serial baseline.
      def processes
        count = ENV.fetch("PROCESSES", DEFAULT_PROCESSES).to_i
        return count if count >= 1

        raise ArgumentError, "PROCESSES must be at least 1 (got #{count})"
      end

      def label(argv)
        argv.first && !argv.first.start_with?("-") ? argv.shift : "run"
      end

      def flag_value(argv, flag)
        index = argv.index(flag)
        index && argv[index + 1]
      end

      def skip
        requested = Set.new(ENV.fetch("SKIP", "").split(",").map(&:strip).reject(&:empty?))
        unsupported = requested - Runner::SKIPPABLE_PHASES
        return requested if unsupported.empty?

        raise ArgumentError,
              "can only SKIP #{Runner::SKIPPABLE_PHASES.join(', ')} (got #{unsupported.to_a.join(', ')})"
      end
    end
  end
end
