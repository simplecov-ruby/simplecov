# frozen_string_literal: true

require "optparse"
require_relative "command_helpers"
require_relative "coverage_file"
require_relative "badge/svg"

module SimpleCov
  module CLI
    module Badge
      extend CommandHelpers

      extend self

      TOTAL_KEYS = {line: "lines", branch: "branches", method: "methods"}.freeze

      def run(args, stdout:, stderr:)
        opts = parse(args)
        key = TOTAL_KEYS[opts.fetch(:criterion)]
        unless key
          return error(stderr,
            "unknown --criterion #{opts.fetch(:criterion).inspect} (expected line, branch, or method)")
        end

        percent = percent_for(opts, key, stderr)
        return 1 unless percent

        label = opts.fetch(:label) || "#{opts.fetch(:criterion)} coverage"
        emit(Svg.render(label: label, percent: percent), opts, stdout)
      end

      def parse(args)
        opts = {input: CLI.default_input, criterion: :line,
                label: nil, output: nil} #: Hash[Symbol, untyped]
        build_parser do |parser|
          parser.on("--input PATH") { |v| opts[:input] = v }
          parser.on("--output PATH") { |v| opts[:output] = v }
          parser.on("--criterion C") { |v| opts[:criterion] = v.to_sym }
          parser.on("--label TEXT") { |v| opts[:label] = v }
        end.parse(args)
        opts
      end

      def percent_for(opts, key, stderr)
        document = CoverageFile.load_document(opts.fetch(:input), command: "badge", stderr: stderr)
        return nil unless document

        totals = document["total"]
        percent = totals.dig(key, "percent") if totals.is_a?(Hash)
        return percent if percent.is_a?(Numeric)

        error_nil(stderr, "no #{opts.fetch(:criterion)} totals in #{opts.fetch(:input)} " \
                          "(was the run measuring #{opts.fetch(:criterion)} coverage?)")
      end

      def emit(svg, opts, stdout)
        opts.fetch(:output) ? File.write(opts.fetch(:output), svg) : stdout.puts(svg)
        0
      end
    end
  end
end
