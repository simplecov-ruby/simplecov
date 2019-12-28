# frozen_string_literal: true

module SimpleCov
  class SourceFile
    #
    # Representing single branch that has been detected in coverage report.
    # Give us support methods that handle needed calculations.
    class Branch
      attr_reader :start_line, :coverage

      def initialize(start_line:, coverage:, inline:, positive:)
        @start_line = start_line
        @coverage   = coverage
        @inline     = inline
        @positive   = positive
      end

      def inline?
        @inline
      end

      def positive?
        @positive
      end

      #
      # Branch is negative
      #
      # @return [Boolean]
      #
      def negative?
        !positive?
      end

      #
      # Return true if there is relevant count defined > 0
      #
      # @return [Boolean]
      #
      def covered?
        coverage.positive?
      end

      #
      # Check if branche missed or not
      #
      # @return [Boolean]
      #
      def missed?
        coverage.zero?
      end

      #
      # Return the sign depends on branch is positive or negative
      #
      # @return [String]
      #
      def badge
        positive? ? "+" : "-"
      end

      # The line on which we want to report the coverage
      #
      # Usually we choose the line above the start of the branch (so that it shows up
      # at if/else) because that
      # * highlights the condition
      # * makes it distinguishable if the first line of the branch is an inline branch
      #   (see the nested_branches fixture)
      #
      def report_line
        if inline?
          start_line
        else
          start_line - 1
        end
      end

      #
      # Return array with coverage count and badge
      #
      # @return [Array]
      #
      def report
        [coverage, badge]
      end
    end
  end
end
