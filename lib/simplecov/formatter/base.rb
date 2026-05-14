# frozen_string_literal: true

module SimpleCov
  module Formatter
    # @api private
    #
    # Shared scaffolding for formatters that write a coverage report to
    # an output directory and emit a "Coverage report generated for X
    # to Y" summary on stdout. Subclasses override `format` to do their
    # actual writing, and may override `message_prefix` (e.g. JSON
    # prepends "JSON ").
    class Base
      # `output_dir` defaults to `SimpleCov.coverage_path` so the at_exit
      # pipeline keeps working unchanged. Pass it explicitly to write
      # somewhere else (handy for tests that don't want to clobber the
      # project's `coverage/` directory).
      def initialize(silent: false, output_dir: nil)
        @silent = silent
        @output_dir = output_dir
      end

    private

      # Subclasses override to prepend a marker (e.g. "JSON ") to the
      # summary line. Default empty for the HTML formatter, which has
      # historically been the unmarked default.
      def message_prefix
        ""
      end

      def output_path
        @output_dir || SimpleCov.coverage_path
      end

      def output_message(result)
        lines = ["#{message_prefix}Coverage report generated for #{result.command_name} to #{output_path}",
                 stats_line(:line, result),
                 branch_stats_line(result),
                 method_stats_line(result)]
        lines.compact.join("\n")
      end

      def branch_stats_line(result)
        stats_line(:branch, result) if SimpleCov.branch_coverage? && result.total_branches&.positive?
      end

      def method_stats_line(result)
        stats_line(:method, result) if SimpleCov.method_coverage? && result.total_methods&.positive?
      end

      def stats_line(criterion, result)
        stat = result.coverage_statistics[criterion]
        Kernel.format(
          "%<label>s coverage: %<covered>d / %<total>d (%<percent>.2f%%)",
          label: criterion.to_s.capitalize,
          covered: stat.covered,
          total: stat.total,
          percent: SimpleCov.round_coverage(stat.percent)
        )
      end
    end
  end
end
