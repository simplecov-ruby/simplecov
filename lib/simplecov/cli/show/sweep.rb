# frozen_string_literal: true

module SimpleCov
  module CLI
    module Show
      module Sweep
        extend self

        def misses(coverage)
          rows = coverage.filter_map do |filename, entry|
            next unless entry.instance_of?(Hash) && entry["lines"].instance_of?(Array)

            missed = Annotator.missed_lines(entry)
            [display_path(filename), missed] unless missed.empty?
          end
          rows.sort_by(&:first)
        end

        def emit(rows, opts, stdout, stderr)
          if opts.fetch(:json)
            stdout.puts(JSON.pretty_generate(rows.map { |path, missed| {path: path, missed: missed} }))
          elsif rows.empty?
            stderr.puts("simplecov show: nothing uncovered")
          else
            rows.each { |path, missed| stdout.puts("#{path}:#{Patch::Output.ranges(missed, ",")}") }
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
