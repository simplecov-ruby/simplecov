# frozen_string_literal: true

module SimpleCov
  module Combine
    #
    # Combine different branch coverage results on single file.
    #
    # Should be called through `SimpleCov.combine`.
    module BranchesCombiner
    module_function

      #
      # Return merged branches or the existed branche if other is missing.
      #
      # Branches inside files are always same if they exists, the difference only in coverage count.
      # Branch coverage report for any conditional case is built from hash, it's key is a condition and
      # it's body is a hash << keys from condition and value is coverage rate >>.
      # ex: branches =>{ [:if, 3, 8, 6, 8, 36] => {[:then, 4, 8, 6, 8, 12] => 1, [:else, 5, 8, 6, 8, 36]=>2}, other conditions...}
      # We create copy of result and update it values depending on the combined branches coverage values.
      #
      # @return [Hash]
      #
      def combine(coverage_a, coverage_b)
        combined_result = coverage_a.clone
        coverage_a.each do |(condition, branches_inside)|
          branches_inside.each do |(branch_key, branch_coverage_value)|
            compared_branch_coverage = coverage_b.dig(condition, branch_key)
            combined_result[condition][branch_key] = branch_coverage_value + compared_branch_coverage.to_i
          end
        end

        combined_result
      end
    end
  end
end
