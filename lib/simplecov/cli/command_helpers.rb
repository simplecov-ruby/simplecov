# frozen_string_literal: true

require "optparse"

module SimpleCov
  module CLI
    module CommandHelpers
      STATS_ROW_FORMAT = "  %<label>-7s %<pct>s (%<covered>d / %<total>d)"

      # Raised by the shared --help switch; `CLI.dispatch` turns it into the
      # command's own slice of the usage text. The explicit handler also overrides
      # optparse's built-in --help, which would print a bare option summary and
      # exit the process outright from inside the parser.
      class HelpRequested < StandardError; end

      def command_name
        name.split("::").last.downcase
      end

      def one?(count)
        (count - 1).zero?
      end

      def error(stderr, message)
        stderr.puts("simplecov #{command_name}: #{message}")
        1
      end

      # `error` returns 1 for an exit status; query helpers need nil so their
      # callers can tell "reported" from a real answer.
      def error_nil(stderr, message)
        error(stderr, message)
        nil
      end

      def recorded_contexts(document, opts, stderr)
        contexts = document["contexts"]
        if contexts.nil?
          return error_nil(stderr, "no test contexts recorded in #{opts.fetch(:input)}. Enable `track_tests` in " \
                                   "your `SimpleCov.start` block and rerun the suite to record them")
        end
        return contexts if contexts.instance_of?(Array) && contexts.all?(String)

        CoverageFile.report_invalid(stderr, command_name, opts.fetch(:input), '"contexts" must be an array of strings')
      end

      def common_options(parser, opts)
        parser.on("--input PATH") { |v| opts[:input] = v }
        parser.on("--json") { opts[:json] = true }
        parser.on("--no-color") { opts[:no_color] = true }
      end

      def build_parser
        OptionParser.new do |parser|
          yield parser if block_given?
          on_help(parser)
        end
      end

      # mutant:disable
      # OptionParser answers `-q` as an unambiguous abbreviation of `--quiet`
      # whether or not the short form is declared.
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
