# frozen_string_literal: true

module SimpleCov
  module Combine
    #
    # Combine two different lines coverage results on same file
    #
    # Should be called through `CoverageAccumulator`.
    module LinesCombiner
    module_function

      # Folds `source` into `target` rather than building a third array.
      # Only for a `target` the caller owns outright: a caller holding a
      # reference to it (e.g. the parsed `coverage` key of a resultset
      # hash being passed into a second merge) would see it change.
      # `source` is never touched.
      #
      # Two runs of the same source file should agree on which lines
      # are coverage-relevant (`nil` for comments / whitespace, `0`+
      # for executable). When they don't, treat "relevant on either
      # side" as relevant rather than masking a real `0` as `nil`,
      # which would silently drop an uncovered line from the
      # denominator and inflate the percentage:
      #
      # => nil + nil = nil
      # => nil + int = int (preserves a relevant-but-uncovered 0)
      # => int + int = int (sum)
      #
      # The loop is written out rather than dispatching a block per
      # element because this is the innermost loop of a merge: a
      # 160-worker run over ~1,800 files folds tens of millions of line
      # counts through it, and a call per count is a measurable share of
      # that.
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
      #
      # The `Integer` tests coerce malformed counts (a "3" written by a
      # hand-edited or foreign resultset, a JSON float) with `to_i`, so
      # external input merges to a wrong answer instead of raising out of
      # the middle of a merge. An `is_a?` per count is far cheaper than
      # the block dispatch this loop exists to avoid, and the well-formed
      # fast path stays branch-for-branch what it was.
      def sum_into(target, source, size)
        index = 0
        while index < size
          if (value = source[index])
            value = value.to_i unless value.is_a?(Integer)
            existing = target[index]
            target[index] = existing.is_a?(Integer) ? existing + value : coerce_add(existing, value)
          end
          index += 1
        end
        target
      end

      # The rare arm: `existing` is nil (line not yet relevant in the
      # target) or malformed external input.
      def coerce_add(existing, value)
        existing.nil? ? value : existing.to_i + value
      end
    end
  end
end
