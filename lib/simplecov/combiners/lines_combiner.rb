# frozen_string_literal: true

module SimpleCov
  module Combiners
    #
    # Combine two different lines coverage results on same file
    #
    class LinesCombiner < BaseCombiner
      def combine
        return existed_coverage unless empty_coverage?
        combine_lines
      end

      def combine_lines
        first_coverage.map.with_index do |first_coverage_val, index|
          second_coverage_val = second_coverage[index]
          merge_line_coverage(first_coverage_val, second_coverage_val)
        end
      end

      #
      # Return depends on value
      #
      # @param [Integer || nil] first_val
      # @param [Integer || nil] second_val
      #
      # Logic:
      #
      # => nil + 0 = nil
      # => nil + nil = nil
      # => int + int = int
      # @return [Integer || nil]
      #
      def merge_line_coverage(first_val, second_val)
        sum = first_val.to_i + second_val.to_i

        if sum.zero? && (first_val.nil? || second_val.nil?)
          nil
        else
          sum
        end
      end
    end
  end
end
