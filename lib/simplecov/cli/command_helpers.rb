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
      # name, which the type checker cannot see is there, and which is
      # ignored rather than cast because a cast is an assignment a
      # mutation can remove without a trace.
      def command_name
        name.split("::").last.downcase
      end

      # Whether a count is exactly one, for choosing singular wording.
      # Spelled as a countdown rather than an equality because two equal
      # Integers are equal through every spelling of the comparison, and
      # none of those spellings can be told apart.
      def one?(count)
        (count - 1).zero?
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
          return error_nil(stderr, "no test contexts recorded in #{opts.fetch(:input)}. Enable `track_tests` in " \
                                   "your `SimpleCov.start` block and rerun the suite to record them")
        end
        return contexts if contexts.instance_of?(Array) && contexts.all?(String)

        CoverageFile.report_invalid(stderr, command_name, opts.fetch(:input), '"contexts" must be an array of strings')
      end

      # The --input / --json / --no-color trio every read-only
      # subcommand accepts.
      def common_options(parser, opts)
        parser.on("--input PATH") { |v| opts[:input] = v }
        parser.on("--json")       { opts[:json] = true }
        parser.on("--no-color")   { opts[:no_color] = true }
      end

      # Every subcommand's parser, with the shared --help switch wired
      # in once here rather than at each of the nine call sites that
      # used to repeat it.
      def build_parser
        OptionParser.new do |parser|
          yield parser if block_given?
          on_help(parser)
        end
      end

      # OptionParser answers `-q` as an unambiguous abbreviation of
      # `--quiet` whether or not the short form is declared, and each
      # command's help text is written by hand rather than rendered from
      # its parser, so declaring the alias is documentation nothing can
      # be asked about.
      # mutant:disable
      def quiet_option(parser, opts)
        parser.on("-q", "--quiet") { opts[:quiet] = true }
      end

      # mutant:disable — optparse matches an abbreviated `-h` against
      # `--help` whether or not the short form is declared, so dropping
      # it changes nothing an example could see. Declared anyway, so the
      # flag appears in the usage text.
      def on_help(parser)
        parser.on("--help", "-h") { raise HelpRequested }
      end

      # The parse scaffold every read-only subcommand repeats: seed the
      # shared defaults (plus the command's own), wire up the common
      # option trio, yield the parser for command-specific flags, and
      # return the parsed opts alongside the positional arguments.
      def parse_common(args, defaults = {})
        opts = {input: CLI.default_input, json: false, no_color: false} #: Hash[Symbol, untyped]
        opts.merge!(defaults)
        rest =
          build_parser do |parser|
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
