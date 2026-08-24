# frozen_string_literal: true

require "optparse"
require_relative "command_helpers"
require_relative "coverage_file"
require_relative "badge/svg"

module SimpleCov
  module CLI
    # `simplecov badge` — render the report's percentage as a flat SVG
    # badge for a README or a CI artifact, with no badge service in the
    # loop. The percent comes from the totals coverage.json already
    # carries, so the badge is generated from the same artifact the
    # other read-only commands consume.
    module Badge
      extend CommandHelpers

    module_function

      TOTAL_KEYS = {line: "lines", branch: "branches", method: "methods"}.freeze

      def run(args, stdout:, stderr:)
        opts = parse(args)
        key = TOTAL_KEYS[opts[:criterion]]
        unless key
          return error(stderr, "unknown --criterion #{opts[:criterion].inspect} (expected line, branch, or method)")
        end

        percent = percent_for(opts, key, stderr)
        return 1 unless percent

        label = opts[:label] || "#{opts[:criterion]} coverage"
        emit(Svg.render(label: label, percent: percent), opts, stdout)
      end

      def parse(args)
        opts = {input: SimpleCov::CLI.default_input, criterion: :line,
                label: nil, output: nil} #: Hash[Symbol, untyped]
        OptionParser.new do |parser|
          parser.on("--input PATH")  { |v| opts[:input] = v }
          parser.on("--output PATH") { |v| opts[:output] = v }
          parser.on("--criterion C") { |v| opts[:criterion] = v.to_sym }
          parser.on("--label TEXT")  { |v| opts[:label] = v }
          on_help(parser)
        end.parse(args)
        opts
      end

      def percent_for(opts, key, stderr)
        document = CoverageFile.load_document(opts[:input], command: "badge", stderr: stderr)
        return nil unless document

        percent = document["total"].is_a?(Hash) ? document["total"].dig(key, "percent") : nil
        return percent if percent.is_a?(Numeric)

        error_nil(stderr, "no #{opts[:criterion]} totals in #{opts[:input]} " \
                          "(was the run measuring #{opts[:criterion]} coverage?)")
      end

      def emit(svg, opts, stdout)
        opts[:output] ? File.write(opts[:output], svg) : stdout.puts(svg)
        0
      end
    end
  end
end
