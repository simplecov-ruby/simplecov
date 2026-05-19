# frozen_string_literal: true

module SimpleCov
  module Formatter
    # @api private
    #
    # Shared scaffolding for formatters that write a coverage report to
    # an output directory and emit a "Coverage report generated for X
    # to Y" summary on stderr (it's a status message, not data).
    # Subclasses override `format` to do their actual writing, and may
    # override `message_prefix` (e.g. JSON prepends "JSON ").
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

      # Emit one summary line per criterion that the run actually
      # measured. The header line ("Coverage report generated for X
      # to Y") is always first; per-criterion lines follow in the
      # order of `result.coverage_statistics` (which is the same
      # insertion order as `SourceFile#coverage_statistics`, which in
      # turn reflects what the user enabled).
      def output_message(result)
        header = "#{message_prefix}Coverage report generated for #{result.command_name} to #{output_path}"
        body   = result.coverage_statistics.filter_map { |criterion, stat| stats_line(criterion, stat) }
        [header, *body].join("\n")
      end

      # Returns nil for branch/method criteria that have nothing to
      # measure (e.g. a file with no branches under branch coverage).
      # Showing "Branch coverage: 0 / 0 (100.00%)" is noise; the older
      # output specifically suppressed it.
      def stats_line(criterion, stat)
        return if criterion != :line && !stat.total.positive?

        percent = SimpleCov.round_coverage(stat.percent)
        Kernel.format(
          "%<label>s coverage: %<covered>d / %<total>d (%<percent>s)",
          label: criterion.to_s.capitalize,
          covered: stat.covered,
          total: stat.total,
          percent: SimpleCov::Color.colorize_percent(percent)
        )
      end
    end
  end
end
