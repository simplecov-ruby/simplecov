# frozen_string_literal: true

module SimpleCov
  module Combine
    #
    # Combine two different lines coverage results on same file
    #
    # Should be called through `SimpleCov.combine`.
    module LinesCombiner
    module_function

      # Build a fresh array sized to the longer input. The previous
      # implementation mutated whichever input was longer in place,
      # which could surprise callers holding a reference to that array
      # (e.g. the parsed `coverage` key of a resultset hash being
      # passed into a second merge).
      def combine(coverage_a, coverage_b)
        size = [coverage_a.size, coverage_b.size].max
        Array.new(size) { |i| merge_line_coverage(coverage_a[i], coverage_b[i]) }
      end

      # Two runs of the same source file should agree on which lines
      # are coverage-relevant (`nil` for comments / whitespace, `0`+
      # for executable). When they don't, treat "relevant on either
      # side" as relevant rather than masking a real `0` as `nil`,
      # which would silently drop an uncovered line from the
      # denominator and inflate the percentage.
      #
      # Logic:
      #
      # => nil + nil = nil
      # => nil + int = int (preserves a relevant-but-uncovered 0)
      # => int + int = int (sum)
      #
      # @param [Integer || nil] first_val
      # @param [Integer || nil] second_val
      # @return [Integer || nil]
      def merge_line_coverage(first_val, second_val)
        return nil if first_val.nil? && second_val.nil?

        first_val.to_i + second_val.to_i
      end
    end
  end
end
