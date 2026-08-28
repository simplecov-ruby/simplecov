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

        extend self

        def emit(stdout, opts, entries, color:)
          return emit_json(stdout, opts, entries) if opts.fetch(:json)
          return stdout.puts("simplecov history: no recorded runs in #{opts.fetch(:input)}") if entries.empty?

          if opts.fetch(:file)
            emit_file(stdout, opts, entries, color)
          else
            emit_totals(stdout, opts, entries, color)
          end
        end

        def emit_totals(stdout, opts, entries, color)
          stdout.puts("Coverage history: #{opts.fetch(:input)} (#{pluralize(entries.length, 'run')})")
          stdout.puts
          emit_criteria_views(stdout, entries, color, "totals")
        end

        # The file view is the totals view scoped to one path: entries
        # record the same {criterion => percent} shape for both.
        def emit_file(stdout, opts, entries, color)
          file = opts.fetch(:file)
          stdout.puts("Coverage history for #{file} (#{pluralize(entries.length, 'run')})")
          stdout.puts
          emit_criteria_views(stdout, entries, color, "files", file)
        end

        # The path is taken apart rather than passed as a list, so each
        # view names its own keys and the views below can dig with it.
        def emit_criteria_views(stdout, entries, color, *path)
          criteria = measured_criteria(entries, path)
          emit_sparklines(stdout, entries, criteria, color, path)
          stdout.puts
          emit_rows(stdout, entries) { |entry| percents_cell(entry, criteria, path) }
        end

        def emit_sparklines(stdout, entries, criteria, color, path)
          width = criteria.map(&:length).max
          criteria.each do |criterion|
            series = entries.map { |entry| numeric(entry.dig(*path, criterion)) }
            stdout.puts("  #{criterion.ljust(width)}  #{sparkline(series)}  #{trend(series, color)}")
          end
        end

        # One row per run: timestamp, branch, short commit, and the
        # view's own cell, columns padded so the rows read as a table.
        def emit_rows(stdout, entries)
          width = entries.map { |entry| branch_of(entry).length }.max
          entries.each do |entry|
            commit = (entry["commit"] || "-")[0, 7].ljust(7)
            stdout.puts("  #{entry['created_at']}  #{branch_of(entry).ljust(width)}  #{commit}  #{yield(entry)}")
          end
        end

        # The branch a run was recorded on, or a dash for a run that
        # recorded none. Read the one way, so the column is padded to
        # the width of the values it actually prints.
        def branch_of(entry)
          entry["branch"] || "-"
        end

        # "line 90.0%  branch 80.0%", or "-" for a run that recorded
        # nothing at the path (a file the run never saw).
        def percents_cell(entry, criteria, path)
          cell = criteria.filter_map do |criterion|
            value = numeric(entry.dig(*path, criterion))
            "#{criterion} #{value}%" if value
          end.join("  ")
          cell.empty? ? "-" : cell
        end

        # Min-max scaled block characters, one per run, a space where
        # the series has no value for that run. A flat series renders at
        # mid height: direction of travel is the message, and a flat
        # line says it plainly.
        # A series with no numbers at all is all gaps, and answering
        # that outright keeps the scale off a range it doesn't have.
        def sparkline(series)
          numeric = series.compact
          return " " * series.length if numeric.empty?

          min = numeric.min
          # The float keeps the scaling below off integer division for a
          # history that recorded whole percentages.
          span = numeric.max - min.to_f
          series.map { |value| value.nil? ? " " : bar(value, min, span) }.join
        end

        def bar(value, min, span)
          span.zero? ? BARS.fetch(3) : BARS.fetch(((value - min) / span * (BARS.length - 1)).round)
        end

        # "90.0% → 100.0%  (+10.0)", the delta colored by its sign.
        def trend(series, color)
          numeric = series.compact
          first = numeric.first
          last = numeric.last
          delta = (last - first).round(2)
          # A drop already carries its own minus, so the sign is a prefix
          # a rise has and a drop has not. Spelled as an absent prefix
          # rather than an empty one, since the two interpolate alike.
          sign = "+" unless delta.negative?
          delta_text = Color.colorize("(#{sign}#{delta})", delta.negative? ? :red : :green, enabled: color)
          "#{first}% → #{last}%  #{delta_text}"
        end

        def emit_json(stdout, opts, entries)
          return stdout.puts(JSON.generate(entries)) unless opts.fetch(:file)

          rows = entries.map do |entry|
            percents = entry.dig("files", opts.fetch(:file))
            {created_at: entry["created_at"], branch: entry["branch"], commit: entry["commit"],
             percents: (percents if percents.instance_of?(Hash))}
          end
          stdout.puts(JSON.generate(rows))
        end

        # Criteria some run recorded a number for at the given path, in
        # canonical order, so a criterion enabled midway still gets its
        # sparkline. A criterion no run recorded a number for is left
        # out: an all-gaps sparkline has no trend to read off it.
        def measured_criteria(entries, path)
          CRITERIA_ORDER.select do |criterion|
            entries.any? do |entry|
              percents = entry.dig(*path)
              percents.instance_of?(Hash) && numeric(percents[criterion])
            end
          end
        end

        def numeric(value)
          value if value.is_a?(Numeric)
        end

        def pluralize(number, noun)
          "#{number} #{noun}#{'s' unless number.eql?(1)}"
        end
      end
    end
  end
end
