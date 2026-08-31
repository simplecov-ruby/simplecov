# frozen_string_literal: true

require "pathname"

module SimpleCov
  module Formatter
    # @api private
    #
    # Shared scaffolding for formatters that write a coverage report to an
    # output directory and emit a "Coverage report generated for X to Y"
    # summary on stderr. Subclasses override `format`, and may override
    # `message_prefix`.
    class Base
      # `output_dir` defaults to `SimpleCov.coverage_path`. Pass it explicitly
      # to write somewhere else.
      def initialize(silent: false, output_dir: nil)
        @silent = silent
        @output_dir = output_dir
      end

    private

      # The one home of the "status lines go to stderr, not through warn"
      # decision (#1225). stderr rather than stdout because this is a status
      # message, not the program's output, so it stays out of pipelines like
      # `rspec -f json`. And `$stderr.puts` rather than `warn` so the line
      # neither reaches `Warning.warn` hooks nor vanishes under `-W0`.
      def emit_status(result)
        $stderr.puts output_message(result) unless @silent # rubocop:disable Style/StderrPuts
      rescue IOError
        # A parallel runner can close a worker's stderr before its at_exit hooks
        # run (rspec-conductor does). Losing the status line must not abort the
        # exit tasks that follow report generation.
      end

      # Subclasses override to prepend a marker (e.g. "JSON ") to the summary
      # line. Empty for the HTML formatter, historically the unmarked default.
      def message_prefix
        ""
      end

      def output_path
        @output_dir || SimpleCov.coverage_path
      end

      # The path shown in the "Coverage report generated for X to Y" status line.
      # Rendered relative to cwd when `output_path` lives inside cwd, with the
      # formatter's `entry_point_filename` appended so the line points at a
      # concrete file a terminal can hyperlink. Paths outside cwd stay
      # absolute; a `../../../tmp/cov` display would be more confusing (#197).
      def displayable_output_path
        directory = relative_or_absolute_output_path
        entry_point = entry_point_filename
        entry_point ? File.join(directory, entry_point) : directory
      end

      def relative_or_absolute_output_path
        absolute = output_path
        relative = Pathname.new(absolute).relative_path_from(Pathname.pwd).to_s
        relative.start_with?("..") ? absolute : relative
      rescue ArgumentError
        # Pathname#relative_path_from raises across mixed absolute/relative
        # inputs, and across Windows drives.
        output_path
      end

      # Subclasses override to name the report's entry-point file, which gets
      # appended to the directory in the status line. The empty body answers
      # nil, which leaves the bare directory in place for any third-party
      # formatter that has no single canonical entry point.
      def entry_point_filename; end

      # One summary line per criterion the run actually measured, in the order
      # of `result.coverage_statistics`, which reflects what the user enabled.
      def output_message(result)
        header = "#{message_prefix}Coverage report generated for #{result.command_name} to #{displayable_output_path}"
        body   = result.coverage_statistics.filter_map { |criterion, stat| stats_line(criterion, stat) }
        [header, *body].join("\n")
      end

      # Returns nil for branch/method criteria that have nothing to measure.
      # Showing "Branch coverage: 0 / 0 (100.00%)" is noise.
      def stats_line(criterion, stat)
        return if !criterion.equal?(:line) && !stat.total.positive?

        percent = SimpleCov.round_coverage(stat.percent)
        # `Symbol#capitalize` answers a Symbol, which `%<label>s` renders as its
        # capitalized name, so the label needs no `to_s` step of its own.
        Kernel.format(
          "%<label>s coverage: %<covered>d / %<total>d (%<percent>s)",
          label: criterion.capitalize,
          covered: stat.covered,
          total: stat.total,
          percent: Color.colorize_percent(percent)
        )
      end
    end
  end
end
