# frozen_string_literal: true

module SimpleCov
  module CLI
    module History
      # Renders the trend: Unicode sparklines scaled to each series'
      # own range (the numbers beside them carry the absolute scale),
      # the per-run rows, and the JSON forms of both views.
      module Output
        BARS = %w[▁ ▂ ▃ ▄ ▅ ▆ ▇ █].freeze

        # The canonical criterion order, which is also the order the
        # rest of SimpleCov presents criteria in.
        CRITERIA_ORDER = %w[line branch method].freeze

      module_function

        def emit(stdout, opts, entries, color:)
          return emit_json(stdout, opts, entries) if opts[:json]
          return stdout.puts("simplecov history: no recorded runs in #{opts[:input]}") if entries.empty?

          if opts[:file]
            emit_file(stdout, opts, entries, color)
          else
            emit_totals(stdout, opts, entries, color)
          end
        end

        def emit_totals(stdout, opts, entries, color)
          stdout.puts("Coverage history: #{opts[:input]} (#{pluralize(entries.length, 'run')})")
          stdout.puts
          criteria = measured_criteria(entries)
          emit_sparklines(stdout, entries, criteria, color)
          stdout.puts
          emit_rows(stdout, entries) { |entry| totals_cell(entry, criteria) }
        end

        def emit_sparklines(stdout, entries, criteria, color)
          width = criteria.map(&:length).max
          criteria.each do |criterion|
            series = entries.map { |entry| numeric(entry.dig("totals", criterion)) }
            stdout.puts("  #{criterion.ljust(width)}  #{sparkline(series)}  #{trend(series, color)}")
          end
        end

        def emit_file(stdout, opts, entries, color)
          file = opts[:file]
          series = entries.map { |entry| numeric(entry.dig("files", file)) }
          stdout.puts("Coverage history for #{file} (#{pluralize(entries.length, 'run')})")
          stdout.puts
          stdout.puts("  #{file}  #{sparkline(series)}  #{trend(series, color)}")
          stdout.puts
          emit_rows(stdout, entries) { |entry| percent_or_dash(entry.dig("files", file)) }
        end

        # One row per run: timestamp, branch, short commit, and the
        # view's own cell, columns padded so the rows read as a table.
        def emit_rows(stdout, entries)
          branch_width = entries.map { |entry| (entry["branch"] || "-").length }.max
          entries.each do |entry|
            branch = (entry["branch"] || "-").ljust(branch_width)
            commit = ((entry["commit"] || "-")[0, 7] || "-").ljust(7)
            stdout.puts("  #{entry['created_at']}  #{branch}  #{commit}  #{yield(entry)}")
          end
        end

        def totals_cell(entry, criteria)
          criteria.filter_map do |criterion|
            value = numeric(entry.dig("totals", criterion))
            "#{criterion} #{value}%" if value
          end.join("  ")
        end

        def percent_or_dash(value)
          value.is_a?(Numeric) ? "#{value}%" : "-"
        end

        # Min-max scaled block characters, one per run, a space where
        # the series has no value for that run. A flat series renders at
        # mid height: direction of travel is the message, and a flat
        # line says it plainly.
        def sparkline(series)
          numeric = series.compact
          min = numeric.min || 0
          span = (numeric.max || 0) - min.to_f
          series.map { |value| value.nil? ? " " : bar(value, min, span) }.join
        end

        def bar(value, min, span)
          span.zero? ? BARS[3] : BARS[((value - min).to_f / span * (BARS.length - 1)).round]
        end

        # "90.0% → 100.0%  (+10.0)", the delta colored by its sign.
        def trend(series, color)
          numeric = series.compact
          first = numeric.first
          last = numeric.last
          delta = (last - first).round(2)
          sign = delta.negative? ? "" : "+"
          delta_text = SimpleCov::Color.colorize("(#{sign}#{delta})", delta.negative? ? :red : :green, enabled: color)
          "#{first}% → #{last}%  #{delta_text}"
        end

        def emit_json(stdout, opts, entries)
          return stdout.puts(JSON.generate(entries)) unless opts[:file]

          rows = entries.map do |entry|
            {created_at: entry["created_at"], branch: entry["branch"], commit: entry["commit"],
             percent: numeric(entry.dig("files", opts[:file]))}
          end
          stdout.puts(JSON.generate(rows))
        end

        # Criteria present anywhere in the history, in canonical order,
        # so a criterion enabled midway still gets its sparkline.
        def measured_criteria(entries)
          present = entries.flat_map { |entry| entry["totals"].is_a?(Hash) ? entry["totals"].keys : [] }.uniq
          CRITERIA_ORDER & present
        end

        def numeric(value)
          value.is_a?(Numeric) ? value : nil
        end

        def pluralize(number, noun)
          "#{number} #{noun}#{'s' unless number == 1}"
        end
      end
    end
  end
end
