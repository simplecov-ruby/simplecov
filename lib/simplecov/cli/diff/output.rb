# frozen_string_literal: true

module SimpleCov
  module CLI
    module Diff
      # Renders the computed delta rows for the terminal: one line per
      # file, sign-colored per-criterion deltas, and the status suffix
      # for files the diff added or removed.
      module Output
        STATUS_SUFFIX = {"added" => "(new file)", "removed" => "(removed)"}.freeze

        extend self

        def emit_text(stdout, rows, color)
          if rows.empty?
            stdout.puts("simplecov diff: no per-file coverage changes")
          else
            rows.each { |row| stdout.puts(format_row(row, color)) }
          end
        end

        def format_row(row, color)
          line = "  #{delta_parts(row, color).join('  ')}  #{row.fetch(:file)}"
          suffix = STATUS_SUFFIX[row.fetch(:status)]
          suffix ? "#{line}  #{suffix}" : line
        end

        def delta_parts(row, color)
          [
            format_delta(row.fetch(:line_delta), "lines", color),
            (format_delta(row.fetch(:branch_delta), "branches", color) if row.fetch(:branch_delta).abs > EPSILON),
            (format_delta(row.fetch(:method_delta), "methods", color) if row.fetch(:method_delta).abs > EPSILON)
          ].compact
        end

        # Deltas are sign-based, not threshold-based: a +5% bump is good
        # (green) and a -5% drop is bad (red), regardless of where the
        # absolute coverage level lands.
        def format_delta(delta, label, color)
          # A drop carries its own minus, so the sign is a prefix a rise
          # has and a drop has not. Spelled as an absent prefix rather
          # than an empty one, since the two format alike.
          sign = "+" if delta.positive?
          text = format("%<sign>s%<delta>6.2f%% %<label>s", sign: sign, delta: delta, label: label)
          Color.colorize(text, delta.negative? ? :red : :green, enabled: color)
        end
      end
    end
  end
end
