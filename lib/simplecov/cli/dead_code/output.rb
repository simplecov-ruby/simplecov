# frozen_string_literal: true

require_relative "../patch/output"

module SimpleCov
  module CLI
    module DeadCode
      # Renders the crossed matrix: the text views with their
      # `path:ranges` rows and summary counts, and the JSON payload,
      # which always carries every category regardless of the view.
      module Output
      module_function

        def emit(stdout, opts, matrix, production)
          return stdout.puts(JSON.generate(json_payload(matrix, production))) if opts[:json]

          stdout.puts("Production coverage: #{opts[:production]}#{window_suffix(production)}")
          stdout.puts
          opts[:untested] ? emit_untested(stdout, matrix) : emit_dead(stdout, matrix)
        end

        def emit_dead(stdout, matrix)
          rows = section(stdout, "Dead code (not run in production, not covered by tests):", matrix, :dead)
          rows += section(stdout, "Possibly dead (not run in production, covered only by tests):", matrix,
                          :possibly_dead)
          return stdout.puts("No dead code found.") if rows.zero?

          dead = count(matrix, :dead)
          possibly = count(matrix, :possibly_dead)
          stdout.puts("#{pluralize(dead, 'dead line')}, #{pluralize(possibly, 'possibly dead line')}")
        end

        def emit_untested(stdout, matrix)
          rows = section(stdout, "Untested code running in production:", matrix, :untested_in_production)
          return stdout.puts("No untested production code found.") if rows.zero?

          stdout.puts("#{pluralize(count(matrix, :untested_in_production), 'untested line')} running in production")
        end

        # Print one category as `path:ranges` rows (empty categories
        # print nothing, not even their heading) and return the row
        # count.
        def section(stdout, heading, matrix, bucket)
          rows = matrix[bucket].sort
          return 0 if rows.empty?

          stdout.puts(heading)
          rows.each do |file, lines|
            marker = matrix[:entire].include?(file) ? " (entire file)" : ""
            stdout.puts("  #{file}:#{Patch::Output.ranges(lines, ',')}#{marker}")
          end
          stdout.puts
          rows.size
        end

        def count(matrix, bucket)
          matrix[bucket].sum { |_file, lines| lines.size }
        end

        def pluralize(number, noun)
          "#{number} #{noun}#{'s' unless number == 1}"
        end

        def window_suffix(production)
          started = production["started_at"]
          updated = production["updated_at"]
          return "" unless started && updated

          " (window #{started} to #{updated})"
        end

        def json_payload(matrix, production)
          payload = {window: {started_at: production["started_at"], updated_at: production["updated_at"]}}
          %i[dead possibly_dead untested_in_production].each do |bucket|
            payload[bucket] = matrix[bucket].sort.map { |file, lines| {file: file, lines: lines} }
          end
          payload
        end
      end
    end
  end
end
