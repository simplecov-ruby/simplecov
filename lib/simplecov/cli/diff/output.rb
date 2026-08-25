# frozen_string_literal: true

module SimpleCov
  module CLI
    module Diff
      # Renders the computed delta rows for the terminal: one line per
      # file, sign-colored per-criterion deltas, and the status suffix
      # for files the diff added or removed.
      module Output
        STATUS_SUFFIX = {"added" => "(new file)", "removed" => "(removed)"}.freeze

      module_function

        def emit_text(stdout, rows, color)
          return stdout.puts("simplecov diff: no per-file coverage changes") if rows.empty?

          rows.each { |row| stdout.puts(format_row(row, color)) }
        end

        def format_row(row, color)
          line = "  #{delta_parts(row, color).join('  ')}  #{row[:file]}"
          suffix = STATUS_SUFFIX[row[:status]]
          suffix ? "#{line}  #{suffix}" : line
        end

        def delta_parts(row, color)
          [
            format_delta(row[:line_delta], "lines", color),
            (format_delta(row[:branch_delta], "branches", color) if row[:branch_delta].abs > EPSILON),
            (format_delta(row[:method_delta], "methods", color)  if row[:method_delta].abs > EPSILON)
          ].compact
        end

        # Deltas are sign-based, not threshold-based: a +5% bump is good
        # (green) and a -5% drop is bad (red), regardless of where the
        # absolute coverage level lands.
        def format_delta(delta, label, color)
          sign = delta.positive? ? "+" : ""
          text = format("%<sign>s%<delta>6.2f%% %<label>s", sign: sign, delta: delta, label: label)
          SimpleCov::Color.colorize(text, delta.negative? ? :red : :green, enabled: color)
        end
      end
    end
  end
end
