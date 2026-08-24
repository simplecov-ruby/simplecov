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

      # Raised by the shared --help switch; `CLI.dispatch` turns it into
      # the command's own slice of the usage text. The explicit handler
      # also overrides optparse's built-in --help, which would print a
      # bare option summary under the host program's banner and exit
      # the process outright, from inside the parser.
      class HelpRequested < StandardError; end

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

      # `error` returns 1 for an exit status; query helpers need nil so
      # their callers can tell "reported" from a real answer.
      def error_nil(stderr, message)
        error(stderr, message)
        nil
      end

      # The document-level context list a `track_tests` recording stores.
      # Its absence means the producing run never recorded, which
      # deserves a pointer at the switch rather than a bare empty answer.
      def recorded_contexts(document, opts, stderr)
        contexts = document["contexts"]
        if contexts.nil?
          return error_nil(stderr, "no test contexts recorded in #{opts[:input]}. Enable `track_tests` in " \
                                   "your `SimpleCov.start` block and rerun the suite to record them")
        end
        return contexts if contexts.is_a?(Array) && contexts.all?(String)

        CoverageFile.report_invalid(stderr, command_name, opts[:input], '"contexts" must be an array of strings')
      end

      # The --input / --json / --no-color trio every read-only
      # subcommand accepts.
      def common_options(parser, opts)
        parser.on("--input PATH") { |v| opts[:input] = v }
        parser.on("--json")       { opts[:json] = true }
        parser.on("--no-color")   { opts[:no_color] = true }
        on_help(parser)
      end

      def on_help(parser)
        parser.on("--help", "-h") { raise HelpRequested }
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
