# frozen_string_literal: true

require "pathname"

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

      # The path shown in the "Coverage report generated for X to Y"
      # status line. Renders relative to cwd when `output_path` lives
      # inside cwd (e.g. `coverage` instead of `/Users/me/proj/coverage`)
      # and appends the formatter's `entry_point_filename` so the line
      # points at a concrete file the user (or a terminal that
      # hyperlinks paths) can act on — e.g. `coverage/index.html`
      # instead of the bare directory `coverage`. Paths outside cwd
      # stay absolute; a `../../../tmp/cov` display would be more
      # confusing than the absolute form. See issue #197.
      def displayable_output_path
        directory = relative_or_absolute_output_path
        entry_point_filename ? File.join(directory, entry_point_filename) : directory
      end

      def relative_or_absolute_output_path
        absolute = output_path
        relative = Pathname.new(absolute).relative_path_from(Pathname.pwd).to_s
        relative.start_with?("..") ? absolute : relative
      rescue ArgumentError
        # Pathname#relative_path_from raises across mixed absolute/
        # relative inputs (and across Windows drives) — keep the
        # absolute form on any unresolvable case.
        output_path
      end

      # Subclasses override to name the report's entry-point file
      # (e.g. `index.html` for HTML, `coverage.json` for JSON), which
      # gets appended to the directory in the status line. Default nil
      # leaves the bare directory in place for any third-party formatter
      # that has no single canonical entry point.
      def entry_point_filename
        nil
      end

      # Emit one summary line per criterion that the run actually
      # measured. The header line ("Coverage report generated for X
      # to Y") is always first; per-criterion lines follow in the
      # order of `result.coverage_statistics` (which is the same
      # insertion order as `SourceFile#coverage_statistics`, which in
      # turn reflects what the user enabled).
      def output_message(result)
        header = "#{message_prefix}Coverage report generated for #{result.command_name} to #{displayable_output_path}"
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
