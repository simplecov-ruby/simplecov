# frozen_string_literal: true

module SimpleCov
  module Combiners
    #
    # Combine different branch coverage results on single file.
    #
    class BranchesCombiner < BaseCombiner
      #
      # Return merged branches or the existed branche if other is missing.
      #
      # @return [Hash]
      #
      def combine
        return existed_coverage unless empty_coverage?
        combine_branches
      end

      #
      # Branches inside files are always same if they exists, the difference only in coverage count.
      # Branch coverage report for any conditional case is built from hash, it's key is a condition and
      # it's body is a hash << keys from condition and value is coverage rate >>.
      # ex: branches =>{ [:if, 3, 8, 6, 8, 36] => {[:then, 4, 8, 6, 8, 12] => 1, [:else, 5, 8, 6, 8, 36]=>2}, other conditions...}
      # We create copy of result and update it values depending on the combined branches coverage values.
      #
      # @return [Hash]
      #
      def combine_branches
        combined_result = first_coverage.clone
        first_coverage.each do |(condition, branches_inside)|
          branches_inside.each do |(branch_key, branch_coverage_value)|
            compared_branch_coverage = second_coverage[condition][branch_key]

            combined_result[condition][branch_key] = branch_coverage_value + compared_branch_coverage
          end
        end

        combined_result
      end
    end
  end
end
