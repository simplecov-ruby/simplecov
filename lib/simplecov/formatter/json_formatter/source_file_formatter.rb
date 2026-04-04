# frozen_string_literal: true

module SimpleCov
  module Formatter
    class JSONFormatter
      class SourceFileFormatter
        def initialize(source_file)
          @source_file = source_file
          @line_coverage = nil
        end

        def format
          result = line_coverage
          result.merge!(branch_coverage) if SimpleCov.branch_coverage?
          result.merge!(method_coverage) if SimpleCov.method_coverage?
          result
        end

      private

        def line_coverage
          @line_coverage ||= {
            lines: lines,
            lines_covered_percent: @source_file.covered_percent
          }
        end

        def branch_coverage
          {
            branches: branches,
            branches_covered_percent: @source_file.branches_coverage_percent
          }
        end

        def method_coverage
          {
            methods: format_methods,
            methods_covered_percent: @source_file.methods_coverage_percent
          }
        end

        def lines
          @source_file.lines.collect do |line|
            parse_line(line)
          end
        end

        def branches
          @source_file.branches.collect do |branch|
            parse_branch(branch)
          end
        end

        def format_methods
          @source_file.methods.collect do |method|
            parse_method(method)
          end
        end

        def parse_line(line)
          return line.coverage unless line.skipped?

          "ignored"
        end

        def parse_branch(branch)
          {
            type: branch.type,
            start_line: branch.start_line,
            end_line: branch.end_line,
            coverage: parse_line(branch)
          }
        end

        def parse_method(method)
          {
            name: method.to_s,
            start_line: method.start_line,
            end_line: method.end_line,
            coverage: parse_line(method)
          }
        end
      end
    end
  end
end
