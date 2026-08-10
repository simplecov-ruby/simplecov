# frozen_string_literal: true

require "optparse"

module SimpleCov
  module CLI
    # Plumbing the subcommands repeat, which their modules `extend`: the
    # standard option trio the read-only commands share, the parse
    # scaffold around it, the one-line error helper (prefixed with the
    # command's own name), and the human-readable stats row `coverage`
    # and `report` both print.
    module CommandHelpers
      STATS_ROW_FORMAT = "  %<label>-7s %<pct>s (%<covered>d / %<total>d)"

      # "simplecov merge: ..." — derived from the extending module's
      # name. The self cast collapses the mixin's view of `self` to the
      # Module that extends it, which is what carries `name`.
      def command_name
        (_ = self).name.split("::").last.downcase
      end

      def error(stderr, message)
        stderr.puts("simplecov #{command_name}: #{message}")
        1
      end

      # The --input / --json / --no-color trio every read-only
      # subcommand accepts.
      def common_options(parser, opts)
        parser.on("--input PATH") { |v| opts[:input] = v }
        parser.on("--json")       { opts[:json] = true }
        parser.on("--no-color")   { opts[:no_color] = true }
      end

      # The parse scaffold every read-only subcommand repeats: seed the
      # shared defaults (plus the command's own), wire up the common
      # option trio, yield the parser for command-specific flags, and
      # return the parsed opts alongside the positional arguments.
      def parse_common(args, defaults = {})
        opts = {input: SimpleCov::CLI.default_input, json: false, no_color: false} #: Hash[Symbol, untyped]
        opts.merge!(defaults)
        rest =
          OptionParser.new do |parser|
            common_options(parser, opts)
            yield parser, opts if block_given?
          end.parse(args)
        [opts, rest]
      end

      def stats_row(label, percent_text, covered, total)
        format(STATS_ROW_FORMAT, label: "#{label}:", pct: percent_text, covered: covered.to_i, total: total.to_i)
      end
    end
  end
end
