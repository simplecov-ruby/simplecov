# frozen_string_literal: true

require "json"

module SimpleCov
  module CLI
    module Patch
      module Output
        OPTIONAL_CRITERIA = %i[branch method].freeze

        extend self

        def emit(stdout, rows, opts)
          if opts.fetch(:json)
            stdout.puts(JSON.pretty_generate(json_rows(rows)))
          else
            emit_text(stdout, rows, CLI.color_enabled?(opts, stdout))
          end
        end

        def emit_text(stdout, rows, color)
          return stdout.puts("simplecov patch: no coverable lines changed") if rows.empty?

          rows.sort_by! { |row| [pct(row.fetch(:line)), row.fetch(:file)] }
          rows.each { |row| stdout.puts(format_row(row, color)) }
          stdout.puts(format_total(rows, color))
        end

        def format_row(row, color)
          line = "  #{criterion_cells(row, color).join('  ')}  #{row.fetch(:file)}"
          note = missing_note(row)
          note.empty? ? line : "#{line}  #{note}"
        end

        def criterion_cells(row, color)
          cells = [criterion_cell("lines", row.fetch(:line), color)]
          cells << criterion_cell("branches", row.fetch(:branch), color) if measured?(row.fetch(:branch))
          cells << criterion_cell("methods", row.fetch(:method), color) if measured?(row.fetch(:method))
          cells
        end

        # A "lines" cell always, "branches" and "methods" cells only when the
        # touched lines actually carried one: a hollow 0/0 cell is noise.
        def criterion_cell(label, stats, color)
          percent = pct(stats)
          cell = Color.colorize(format("%6.2f%%", percent), percent >= 100 ? :green : :red, enabled: color)
          "#{cell} (#{stats.fetch(:covered)}/#{stats.fetch(:relevant)}) #{label}"
        end

        def missing_note(row)
          parts = [] #: Array[String]
          parts << "missing #{ranges(row.fetch(:line).fetch(:missing))}" if row.fetch(:line).fetch(:missing).any?
          OPTIONAL_CRITERIA.each do |criterion|
            stats = row.fetch(criterion)
            parts << "#{criterion} #{ranges(stats.fetch(:missing))}" if measured?(stats) && stats.fetch(:missing).any?
          end
          parts.join("  ")
        end

        def format_total(rows, color)
          totals = {line: sum_stats(rows, :line), branch: sum_stats(rows, :branch), method: sum_stats(rows, :method)}
          "  Patch coverage: #{criterion_cells(totals, color).join(', ')}"
        end

        def json_rows(rows)
          rows.map do |row|
            data = {file: row.fetch(:file), line: row.fetch(:line).merge(percent: pct(row.fetch(:line)))}
            OPTIONAL_CRITERIA.each do |criterion|
              stats = row.fetch(criterion)
              data[criterion] = stats.merge(percent: pct(stats)) if measured?(stats)
            end
            data
          end
        end

        # Branch and method stats are nil when the report never measured them, and
        # 0/0 when the change touched none.
        def measured?(stats)
          stats.is_a?(Hash) && stats.fetch(:relevant).positive?
        end

        # Collapses a sorted line list into ranges: [41, 42, 43, 47] -> "41-43, 47".
        # The show subcommand borrows this with a bare-comma separator for its
        # greppable `path:40,52-58,71` form.
        def ranges(numbers, separator = ", ")
          numbers.slice_when { |prev, curr| curr > prev + 1 }.each_with_object(+"") do |run, out|
            out << separator unless out.empty?
            out << (run.one? ? only(run) : span(run))
          end
        end

        # mutant:disable
        def only(run)
          format("%<only>d", only: run.first)
        end

        def span(run)
          format("%<from>d-%<to>d", from: run.first, to: run.last)
        end

        def sum_stats(rows, criterion)
          stats = rows.filter_map { |row| row.fetch(criterion) }
          {covered: stats.sum { |stat| stat.fetch(:covered) }, relevant: stats.sum { |stat| stat.fetch(:relevant) }}
        end

        def pct(stats)
          relevant = stats.fetch(:relevant)
          return 100.0 if relevant.zero?

          (stats.fetch(:covered).to_f / relevant * 100).round(2)
        end

        # No --minimum is report-only. With one, every measured criterion must clear
        # the floor, and `short?` never fails an unmeasured one.
        def gate(rows, minimum)
          return 0 unless minimum

          below = %i[line branch method].any? { |criterion| short?(sum_stats(rows, criterion), minimum) }
          below ? 1 : 0
        end

        # Cross-multiplied rather than compared as percentages so neither rounding
        # nor float division can shift the verdict at the boundary: reading the
        # displayed `pct` would round a 19_999/20_000 patch up to 100 and pass it
        # against `--minimum 100`, while dividing makes 23/40 compute as 57.4999...
        # and fail an exactly-57.5% patch. The minimum becomes an exact Rational
        # from its own text, and `covered * 100` is an integer, so the comparison is
        # exact. A criterion with nothing relevant never falls short.
        def short?(stats, minimum)
          stats.fetch(:covered) * 100 < Rational(minimum.to_s) * stats.fetch(:relevant)
        end
      end
    end
  end
end
