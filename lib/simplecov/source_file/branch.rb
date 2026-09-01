# frozen_string_literal: true

module SimpleCov
  class SourceFile
    class Branch
      attr_reader :start_line, :end_line, :coverage, :type

      def initialize(start_line:, end_line:, coverage:, inline:, type:)
        @start_line = start_line
        @end_line = end_line
        @coverage = coverage
        @inline = inline
        @type = type
        @skipped = false
      end

      def inline?
        @inline
      end

      def covered?
        !skipped? && coverage.positive?
      end

      def missed?
        !skipped? && coverage.zero?
      end

      # Usually the line above the start of the branch, so that it shows up at the
      # if/else. That highlights the condition, and makes it distinguishable when
      # the first line of the branch is itself an inline branch.
      def report_line
        if inline?
          start_line
        else
          start_line - 1
        end
      end

      def skipped!
        @skipped = true
      end

      def skipped?
        @skipped
      end

      def overlaps_with?(line_range)
        start_line <= line_range.end && end_line >= line_range.begin
      end

      def report
        [type, coverage]
      end
    end
  end
end
