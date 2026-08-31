# frozen_string_literal: true

module SimpleCov
  class SourceFile
    class Line
      attr_reader :src, :line_number, :coverage, :skipped

      alias source src
      alias line line_number
      alias number line_number

      def initialize(src, line_number, coverage)
        raise ArgumentError, "Only String accepted for source" unless src.is_a?(String)
        raise ArgumentError, "Only Integer accepted for line_number" unless line_number.is_a?(Integer)
        unless coverage.is_a?(Integer) || coverage.nil?
          raise ArgumentError, "Only Integer and nil accepted for coverage"
        end

        @src         = src
        @line_number = line_number
        @coverage    = coverage
        @skipped     = false
      end

      # Asking `covered?` rather than reading the count a second time keeps the two
      # answers from ever disagreeing, and `never?` ahead of it is what keeps a
      # line with no coverage at all out of the missed column.
      def missed?
        !never? && !skipped? && !covered?
      end

      def covered?
        !skipped? && coverage.to_i.positive?
      end

      def never?
        !skipped? && coverage.nil?
      end

      def skipped!
        @skipped = true
      end

      def skipped?
        skipped
      end

      def status
        return "skipped" if skipped?
        return "never" if never?
        return "missed" if missed?

        "covered"
      end
    end
  end
end
