# frozen_string_literal: true

module SimpleCov
  module CLI
    module Show
      # The bare-invocation project sweep: every file with misses, in
      # the compact `path:ranges` form or as JSON — one command whose
      # output is the whole project's uncovered surface, ready for a
      # grep or a coding agent.
      module Sweep
      module_function

        # [display path, missed lines] per file with misses, sorted,
        # with paths under SimpleCov.root shown project-relative.
        def misses(coverage)
          rows = coverage.filter_map do |filename, entry|
            next unless entry.is_a?(Hash) && entry["lines"].is_a?(Array)

            missed = Annotator.missed_lines(entry)
            [display_path(filename), missed] unless missed.empty?
          end
          rows.sort_by(&:first)
        end

        def emit(rows, opts, stdout, stderr)
          if opts[:json]
            stdout.puts(JSON.pretty_generate(rows.map { |path, missed| {path: path, missed: missed} }))
          elsif rows.empty?
            stderr.puts("simplecov show: nothing uncovered")
          else
            rows.each { |path, missed| stdout.puts("#{path}:#{Patch::Output.ranges(missed, ',')}") }
          end
          0
        end

        def display_path(filename)
          filename.delete_prefix("#{File.expand_path(SimpleCov.root)}/")
        end
      end
    end
  end
end
