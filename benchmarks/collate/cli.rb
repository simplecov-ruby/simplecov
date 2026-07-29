# frozen_string_literal: true

require_relative "shape"
require_relative "runner"

module CollateBenchmark
  # Turns `ARGV` and the environment into a `Runner`. See benchmarks/collate.rb
  # for the documented set of knobs.
  module CLI
    DEFAULT_SCALE = 4

    # `resultsets` rather than `count`, which would shadow `Struct#count`.
    Options = Struct.new(:label, :resultsets, :scale, :skip, :rebuild, :baseline, :breakdown,
                         keyword_init: true)

    class << self
      def run(argv)
        Runner.new(options(argv)).call
      end

      def options(argv)
        argv = argv.dup
        Options.new(
          label: label(argv),
          baseline: flag_value(argv, "--baseline"),
          resultsets: ENV.fetch("COUNT", Shape::RESULTSETS).to_i,
          scale: ENV.fetch("SCALE", DEFAULT_SCALE).to_i,
          skip: skip,
          rebuild: ENV["REBUILD"] == "1",
          breakdown: ENV["BREAKDOWN"] == "1"
        )
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
