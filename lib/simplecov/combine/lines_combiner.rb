# frozen_string_literal: true

module SimpleCov
  module Combine
    #
    # Combine two different lines coverage results on same file
    #
    # Should be called through `CoverageAccumulator`.
    module LinesCombiner
      extend self

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
        # A shorter target grows to the source's length, and `fill` on a
        # negative length is the no-op the already-long-enough case wants.
        target.fill(nil, target.size, size - target.size)
        sum_into(target, source, size)
      end

      # Split out only to keep `merge_into` short; it is the same loop.
      #
      # Both sides go through `to_i`, which is what keeps the merge total
      # over external input: a count a hand-edited or foreign resultset
      # wrote as "3", or as a JSON float, merges to a wrong answer instead
      # of raising out of the middle of a merge. On the accumulated side
      # it doubles as the nil arm, where a line the target does not yet
      # consider relevant leaves the incoming count standing alone.
      # `Integer#to_i` answers the receiver, so the well-formed path pays
      # one immediate call per count and nothing else.
      def sum_into(target, source, size)
        index = 0
        while index < size
          if (value = source[index])
            target[index] = target.at(index).to_i + value.to_i
          end
          index += 1
        end
        target
      end
    end
  end
end
