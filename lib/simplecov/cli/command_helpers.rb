# frozen_string_literal: true

module SimpleCov
  module CLI
    # Plumbing the subcommands repeat, which their modules `extend`: the
    # standard option trio the read-only commands share, the one-line
    # error helper (prefixed with the command's own name), and the
    # human-readable stats row `coverage` and `report` both print.
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

      def stats_row(label, percent_text, covered, total)
        format(STATS_ROW_FORMAT, label: "#{label}:", pct: percent_text, covered: covered.to_i, total: total.to_i)
      end
    end
  end
end
