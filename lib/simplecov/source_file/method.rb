# frozen_string_literal: true

module SimpleCov
  class SourceFile
    # Represents a single method detected in coverage data.
    # Provides helpers similar to Branch for coverage status.
    class Method
      attr_reader :source_file, :coverage, :class_name, :method_name,
                  :start_line, :start_col, :end_line, :end_col

      def initialize(source_file, info, coverage)
        @source_file = source_file
        @class_name, @method_name, @start_line, @start_col, @end_line, @end_col = info
        @coverage = coverage
      end

      def covered?
        !skipped? && coverage.positive?
      end

      # Criterion-level skips (`# simplecov:disable` /
      # `# simplecov:disable method` regions) arrive via `skipped!` from
      # MethodBuilder. Deliberately NOT derived from the lines' skip
      # state: a line-only directive around a def must not remove the
      # method from method totals. Without line info there is nothing to
      # report against, so such a method stays skipped.
      def skipped?
        return @skipped if defined?(@skipped)

        @skipped = lines.empty?
      end

      # Flag the method as skipped directly, without going through its lines.
      def skipped!
        @skipped = true
      end

      def missed?
        !skipped? && coverage.zero?
      end

      def lines
        @lines ||= start_line && end_line ? source_file.lines[(start_line - 1)..(end_line - 1)] || [] : []
      end

      # Whether this method's source range intersects the given inclusive line range.
      def overlaps_with?(line_range)
        return false unless start_line && end_line

        start_line <= line_range.end && end_line >= line_range.begin
      end

      def to_s
        "#{class_name}##{method_name}"
      end
    end
  end
end
