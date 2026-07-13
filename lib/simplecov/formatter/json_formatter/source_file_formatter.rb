# frozen_string_literal: true

module SimpleCov
  module Formatter
    class JSONFormatter
      # Renders a single `SimpleCov::SourceFile` as the per-file payload
      # in coverage.json: source code plus per-enabled-criterion arrays
      # and totals.
      class SourceFileFormatter
        def initialize(source_file, include_source: true)
          @source_file = source_file
          @include_source = include_source
        end

        def call
          result = @include_source ? format_source_code : {} #: Hash[Symbol, untyped]
          result.merge!(line_coverage_section) if line_coverage_enabled?
          result.merge!(branch_coverage_section) if SimpleCov.branch_coverage?
          result.merge!(method_coverage_section) if SimpleCov.method_coverage?
          result
        end

      private

        # `:oneshot_line` is a synonym for `:line` for stats purposes
        # (see `SimpleCov.coverage_statistics_key`), so treat either as
        # "line coverage is on" for the line-block emit decisions.
        def line_coverage_enabled?
          SimpleCov.coverage_criterion_enabled?(:line) || SimpleCov.coverage_criterion_enabled?(:oneshot_line)
        end

        def format_source_code
          {source: @source_file.lines.map { |line| ensure_utf8(line.src.chomp) }}
        end

        def ensure_utf8(str)
          str.encode("UTF-8", invalid: :replace, undef: :replace)
        end

        def line_coverage_section
          covered = @source_file.covered_lines.size
          missed = @source_file.missed_lines.size
          {
            lines: @source_file.lines.map { |line| format_line(line) },
            lines_covered_percent: @source_file.covered_percent,
            covered_lines: covered,
            missed_lines: missed,
            omitted_lines: @source_file.never_lines.size,
            total_lines: covered + missed
          }
        end

        def branch_coverage_section
          {
            branches: @source_file.branches.map { |branch| format_branch(branch) },
            branches_covered_percent: @source_file.covered_percent(:branch),
            covered_branches: @source_file.covered_branches.size,
            missed_branches: @source_file.missed_branches.size,
            total_branches: @source_file.total_branches.size
          }
        end

        def method_coverage_section
          {
            methods: @source_file.methods.map { |method| format_method(method) },
            methods_covered_percent: @source_file.covered_percent(:method),
            covered_methods: @source_file.covered_methods.size,
            missed_methods: @source_file.missed_methods.size,
            total_methods: @source_file.methods.size
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
