# frozen_string_literal: true

module SimpleCov
  module Combine
    module LinesCombiner
      extend self

      # Folds `source` into `target` rather than building a third array, so only
      # for a `target` the caller owns outright: a caller still holding a
      # reference would see it change. `source` is never touched.
      #
      # Two runs of the same source file should agree on which lines are
      # coverage-relevant (`nil` for comments, `0`+ for executable). When they
      # don't, "relevant on either side" wins rather than masking a real `0` as
      # `nil`, which would drop an uncovered line from the denominator:
      #
      #   nil + nil = nil
      #   nil + int = int (preserves a relevant-but-uncovered 0)
      #   int + int = int (sum)
      def merge_into(target, source)
        return target unless source
        return source.dup unless target

        size = source.size
        target.fill(nil, target.size, size - target.size)
        sum_into(target, source, size)
      end

      # The loop is written out rather than dispatching a block per element
      # because this is the innermost loop of a merge: a 160-worker run over
      # ~1,800 files folds tens of millions of line counts through it.
      #
      # Both sides go through `to_i`, which is what keeps the merge total over
      # external input: a count a hand-edited or foreign resultset wrote as "3" or
      # as a JSON float merges to a wrong answer instead of raising out of the
      # middle of a merge. On the accumulated side it doubles as the nil arm.
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
