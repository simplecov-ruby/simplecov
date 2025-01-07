# frozen_string_literal: true

module SimpleCov
  module Combine
    #
    # Combine two different lines coverage results on same file
    #
    # Should be called through `SimpleCov.combine`.
    module LinesCombiner
    module_function

      def combine(coverage_a, coverage_b)
        coverage_a
          .zip(coverage_b)
          .map do |coverage_a_val, coverage_b_val|
            merge_line_coverage(coverage_a_val, coverage_b_val)
          end
      end

      # Return depends on coverage in a specific line
      #
      # @param [Integer || nil] first_val
      # @param [Integer || nil] second_val
      #
      # Logic:
      #
      # => nil + 0 = nil
      # => nil + nil = nil
      # => int + int = int
      #
      # @return [Integer || nil]
      def merge_line_coverage(first_val, second_val)
        if first_val && second_val
          first_val + second_val
        elsif first_val
          first_val.zero? ? nil : first_val
        elsif second_val
          second_val.zero? ? nil : second_val
        end
      end
    end
  end
end
