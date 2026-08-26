# frozen_string_literal: true

require "json"

module SimpleCov
  module CLI
    module Patch
      # Turn the scored rows into text or JSON on stdout, and into the
      # `--minimum` gate's exit status.
      module Output
        # The criteria that appear only when the change touched one;
        # lines always score.
        OPTIONAL_CRITERIA = %i[branch method].freeze

      module_function

        def emit(stdout, rows, opts)
          if opts[:json]
            stdout.puts(JSON.pretty_generate(json_rows(rows)))
          else
            emit_text(stdout, rows, SimpleCov::CLI.color_enabled?(opts, stdout))
          end
        end

        def emit_text(stdout, rows, color)
          return stdout.puts("simplecov patch: no coverable lines changed") if rows.empty?

          rows.sort_by! { |row| [pct(row[:line]), row[:file]] }
          rows.each { |row| stdout.puts(format_row(row, color)) }
          stdout.puts(format_total(rows, color))
        end

        def format_row(row, color)
          line = "  #{criterion_cells(row, color).join('  ')}  #{row[:file]}"
          note = missing_note(row)
          note.empty? ? line : "#{line}  #{note}"
        end

        # A "lines" cell always, "branches" and "methods" cells only when the
        # touched lines actually carried one — a hollow 0/0 cell is noise.
        # Shared by the per-file row and the total, so the branch and method
        # entries are stats hashes or nil.
        def criterion_cells(row, color)
          cells = [criterion_cell("lines", row[:line], color)]
          cells << criterion_cell("branches", row[:branch], color) if measured?(row[:branch])
          cells << criterion_cell("methods", row[:method], color) if measured?(row[:method])
          cells
        end

        def criterion_cell(label, stats, color)
          percent = pct(stats)
          cell = SimpleCov::Color.colorize(format("%6.2f%%", percent), percent >= 100 ? :green : :red, enabled: color)
          "#{cell} (#{stats[:covered]}/#{stats[:relevant]}) #{label}"
        end

        def missing_note(row)
          parts = [] #: Array[String]
          parts << "missing #{ranges(row[:line][:missing])}" if row[:line][:missing].any?
          OPTIONAL_CRITERIA.each do |criterion|
            stats = row[criterion]
            parts << "#{criterion} #{ranges(stats[:missing])}" if measured?(stats) && stats[:missing].any?
          end
          parts.join("  ")
        end

        def format_total(rows, color)
          totals = {line: sum_stats(rows, :line), branch: sum_stats(rows, :branch), method: sum_stats(rows, :method)}
          "  Patch coverage: #{criterion_cells(totals, color).join(', ')}"
        end

        def json_rows(rows)
          rows.map do |row|
            data = {file: row[:file], line: row[:line].merge(percent: pct(row[:line]))}
            OPTIONAL_CRITERIA.each do |criterion|
              stats = row[criterion]
              data[criterion] = stats.merge(percent: pct(stats)) if measured?(stats)
            end
            data
          end
        end

        # Whether a criterion scored anything for this row or total: branch
        # and method stats are nil when the report never measured them, and
        # 0/0 when the change touched none.
        def measured?(stats)
          stats.is_a?(Hash) && stats[:relevant].positive?
        end

        # Collapse a sorted line list into ranges: [41, 42, 43, 47] -> "41-43, 47".
        # The show subcommand borrows this with a bare-comma separator for
        # its greppable `path:40,52-58,71` form.
        def ranges(numbers, separator = ", ")
          numbers.slice_when { |prev, curr| curr > prev + 1 }
                 .map { |run| run.size == 1 ? run.first.to_s : "#{run.first}-#{run.last}" }
                 .join(separator)
        end

        # Sum a criterion's {covered, relevant} across rows; branch stats are nil
        # on rows from a line-only report, so those are skipped.
        def sum_stats(rows, criterion)
          stats = rows.filter_map { |row| row[criterion] }
          {covered: stats.sum { |stat| stat[:covered] }, relevant: stats.sum { |stat| stat[:relevant] }}
        end

        def pct(stats)
          relevant = stats[:relevant]
          return 100.0 if relevant.zero?

          (stats[:covered].to_f / relevant * 100).round(2)
        end

        # No --minimum is report-only (exit 0). With one, every measured
        # criterion must clear the floor: line coverage, and branch and
        # method coverage over the touched branches and methods when the
        # report carries them (`short?` never fails an unmeasured one).
        def gate(rows, minimum)
          return 0 unless minimum

          below = %i[line branch method].any? { |criterion| short?(sum_stats(rows, criterion), minimum) }
          below ? 1 : 0
        end

        # Whether a criterion falls below the floor. Cross-multiplied rather
        # than compared as percentages so neither rounding nor float
        # division can shift the verdict at the boundary: reading the
        # displayed `pct` would round a 19_999/20_000 (99.995%) patch up to
        # 100 and pass it against `--minimum 100`, while dividing
        # (`covered / relevant * 100`) makes 23/40 compute as 57.4999… and
        # fail an exactly-57.5% patch. The minimum becomes an exact Rational
        # from its own text (`64.4` is not representable in binary, so
        # `64.4 * 250` lands at 16_100.000…2 and fails a patch at exactly
        # 64.4%), and `covered * 100` is an integer, so the comparison is
        # exact. A criterion with nothing relevant never falls short.
        def short?(stats, minimum)
          relevant = stats[:relevant]
          return false if relevant.zero?

          stats[:covered] * 100 < Rational(minimum.to_s) * relevant
        end
      end
    end
  end
end
