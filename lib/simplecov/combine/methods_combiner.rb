# frozen_string_literal: true

module SimpleCov
  module Combine
    #
    # Combine different method coverage results on a single file.
    #
    # Should be called through `SimpleCov.combine`.
    module MethodsCombiner
    module_function

      #
      # Return merged methods or the existing methods if other is missing.
      #
      # Method coverage is a flat hash mapping method identifiers to hit counts.
      # Combining sums the hit counts for matching methods and preserves methods
      # that only appear in one result.
      #
      # @return [Hash]
      #
      def combine(coverage_a, coverage_b)
        coverage_a.merge(coverage_b) { |_key, a_count, b_count| a_count + b_count }
      end
    end
  end
end
