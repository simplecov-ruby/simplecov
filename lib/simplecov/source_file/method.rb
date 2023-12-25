# frozen_string_literal: true

module SimpleCov
  class SourceFile
    class Method
      attr_reader :source_file, :coverage, :klass, :method, :start_line, :start_col, :end_line, :end_col

      def initialize(source_file, info, coverage)
        @source_file = source_file
        @klass, @method, @start_line, @start_col, @end_line, @end_col = info
        @coverage = coverage
      end

      def covered?
        !skipped? && coverage.positive?
      end

      def skipped?
        return @skipped if defined?(@skipped)

        @skipped = lines.all?(&:skipped?)
      end

      def missed?
        !skipped? && coverage.zero?
      end

      def lines
        @lines ||= source_file.lines[(start_line - 1)..(end_line - 1)]
      end

      def to_s
        "#{klass}##{method}"
      end
    end
  end
end
