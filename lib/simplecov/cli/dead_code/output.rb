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
          last_seen = production.fetch("last_seen")
          opts[:untested] ? emit_untested(stdout, matrix, last_seen) : emit_dead(stdout, matrix, last_seen)
        end

        def emit_dead(stdout, matrix, last_seen)
          rows = section(stdout, "Dead code (not run in production, not covered by tests):", matrix, :dead,
                         last_seen)
          rows += section(stdout, "Possibly dead (not run in production, covered only by tests):", matrix,
                          :possibly_dead, last_seen)
          return stdout.puts("No dead code found.") if rows.zero?

          dead = count(matrix, :dead)
          possibly = count(matrix, :possibly_dead)
          stdout.puts("#{pluralize(dead, 'dead line')}, #{pluralize(possibly, 'possibly dead line')}")
        end

        def emit_untested(stdout, matrix, last_seen)
          rows = section(stdout, "Untested code running in production:", matrix, :untested_in_production, last_seen)
          return stdout.puts("No untested production code found.") if rows.zero?

          stdout.puts("#{pluralize(count(matrix, :untested_in_production), 'untested line')} running in production")
        end

        # Print one category as `path:ranges` rows (empty categories
        # print nothing, not even their heading) and return the row
        # count.
        def section(stdout, heading, matrix, bucket, last_seen)
          rows = matrix[bucket].sort
          return 0 if rows.empty?

          stdout.puts(heading)
          rows.each do |file, lines|
            stdout.puts("  #{file}:#{Patch::Output.ranges(lines, ',')}#{markers(matrix, file, last_seen)}")
          end
          stdout.puts
          rows.size
        end

        # The row's parenthesized evidence. "entire file" says every
        # relevant line skipped production; "last run" dates the store's
        # last sighting of the file, which for a dead or possibly dead
        # row means other lines of the file (or lines the report deems
        # irrelevant) ran then, and its absence means the window never
        # saw the file at all. Both can hold at once.
        def markers(matrix, file, last_seen)
          markers = [] #: Array[String]
          markers << "entire file" if matrix[:entire].include?(file)
          stamp = last_seen[file]
          markers << "last run #{stamp[0, 10]}" if stamp.is_a?(String)
          markers.empty? ? "" : " (#{markers.join(', ')})"
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
          last_seen = production.fetch("last_seen")
          payload = {window: {started_at: production["started_at"], updated_at: production["updated_at"]}}
          %i[dead possibly_dead untested_in_production].each do |bucket|
            payload[bucket] = matrix[bucket].sort.map { |file, lines| json_entry(file, lines, last_seen) }
          end
          payload
        end

        # JSON carries the full stamp where the text views print its
        # date, and omits the key for a file the window never saw.
        def json_entry(file, lines, last_seen)
          entry = {file: file, lines: lines} #: Hash[Symbol, untyped]
          stamp = last_seen[file]
          entry[:last_seen] = stamp if stamp.is_a?(String)
          entry
        end
      end
    end
  end
end
