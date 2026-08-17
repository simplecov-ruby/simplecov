# frozen_string_literal: true

module SimpleCov
  module Formatter
    class JSONFormatter
      # Renders a single `SimpleCov::SourceFile` as the per-file payload
      # in coverage.json: source code plus per-enabled-criterion arrays
      # and totals.
      class SourceFileFormatter
        class << self
          def call(source_file, include_source: true, contexts: nil)
            result = include_source ? format_source_code(source_file) : {} #: Hash[Symbol, untyped]
            result.merge!(line_coverage_section(source_file)) if SimpleCov.line_coverage?
            result.merge!(branch_coverage_section(source_file)) if SimpleCov.branch_coverage?
            result.merge!(method_coverage_section(source_file)) if SimpleCov.method_coverage?
            result.merge!(contexts_section(source_file, contexts)) if contexts
            result
          end

        private

          # The file's per-context bitmaps in the map's own wire encoding.
          # An untouched file gets no key at all: under a present
          # document-level `contexts` array, absence already says "no
          # recorded context executed this file".
          def contexts_section(source_file, contexts)
            bitmaps = contexts.serialized_bitmaps_for(source_file.filename)
            bitmaps.empty? ? {} : {contexts: bitmaps}
          end

          # No per-line encoding conversion here: SourceLoader guarantees
          # every line leaves it as valid UTF-8 (transcoding declared
          # encodings, scrubbing invalid bytes), and the converter copy
          # this used to make per line was the single largest allocation
          # source in formatting a large report.
          def format_source_code(source_file)
            {source: source_file.lines.map { |line| line.src.chomp }}
          end

          def line_coverage_section(source_file)
            covered = source_file.covered_lines.size
            missed = source_file.missed_lines.size
            {
              lines: source_file.lines.map { |line| format_line(line) },
              lines_covered_percent: source_file.covered_percent,
              covered_lines: covered,
              missed_lines: missed,
              omitted_lines: source_file.never_lines.size,
              total_lines: covered + missed
            }
          end

          def branch_coverage_section(source_file)
            {
              branches: source_file.branches.map { |branch| format_branch(branch) },
              branches_covered_percent: source_file.covered_percent(:branch),
              covered_branches: source_file.covered_branches.size,
              missed_branches: source_file.missed_branches.size,
              total_branches: source_file.total_branches.size
            }
          end

          def method_coverage_section(source_file)
            covered = source_file.covered_methods.size
            missed = source_file.missed_methods.size

            {
              methods: source_file.methods.map { |method| format_method(method) },
              methods_covered_percent: source_file.covered_percent(:method),
              covered_methods: covered,
              missed_methods: missed,
              total_methods: covered + missed
            }
          end

          def format_line(line)
            line.skipped? ? "ignored" : line.coverage
          end

          def format_branch(branch)
            {
              type: branch.type,
              start_line: branch.start_line,
              end_line: branch.end_line,
              coverage: format_line(branch),
              inline: branch.inline?,
              report_line: branch.report_line
            }
          end

          def format_method(method)
            {
              name: method.to_s,
              start_line: method.start_line,
              end_line: method.end_line,
              coverage: format_line(method)
            }
          end
        end
      end
    end
  end
end
