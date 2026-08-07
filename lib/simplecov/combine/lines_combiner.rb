# frozen_string_literal: true

module SimpleCov
  module Combine
    #
    # Combine two different lines coverage results on same file
    #
    # Should be called through `CoverageAccumulator`.
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

      # Folds `source` into `target` rather than building a third array.
      # Only for a `target` the caller owns outright — see the note on
      # `combine` above for why that matters.
      #
      # The loop is written out instead of going through
      # `merge_line_coverage` per element because this is the innermost loop
      # of a merge: a 160-worker run over ~1,800 files folds tens of millions
      # of line counts through it, and a block call per count is a
      # measurable share of that.
      #
      # @return [Array] the array to keep — `target` itself once there is one
      def merge_into(target, source)
        return target unless source
        return source.dup unless target

        size = source.size
        target.concat(Array.new(size - target.size)) if target.size < size
        sum_into(target, source, size)
      end

      # Split out only to keep `merge_into` short; it is the same loop.
      def sum_into(target, source, size)
        index = 0
        while index < size
          value = source[index]
          unless value.nil?
            existing = target[index]
            target[index] = existing.nil? ? value : existing + value
          end
          index += 1
        end
        target
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
