# frozen_string_literal: true

require_relative "../source_file/ruby_data_parser"

module SimpleCov
  module Combine
    #
    # Combine different branch coverage results on single file.
    #
    # Should be called through `SimpleCov.combine`.
    module BranchesCombiner
    module_function

      #
      # Return merged branches or the existed branch if other is missing.
      #
      # Branches inside files are always same if they exist, the difference only in coverage count.
      # Branch coverage report for any conditional case is built from hash, it's key is a condition and
      # it's body is a hash << keys from condition and value is coverage rate >>.
      # ex: branches => { [:if, 3, 8, 6, 8, 36] =>
      #                     {[:then, 4, 8, 6, 8, 12] => 1, [:else, 5, 8, 6, 8, 36] => 2}, ... }
      # We create copy of result and update it values depending on the combined branches coverage values.
      #
      # @return [Hash]
      #
      def combine(coverage_a, coverage_b)
        merged = {} #: Hash[untyped, [untyped, Hash[untyped, untyped]]]
        combined = [coverage_a, coverage_b].each_with_object(merged) do |coverage, memo|
          coverage.each do |condition, branches_inside|
            condition_key = tuple_identity(condition)
            condition_tuple, merged_branches = memo[condition_key] ||= [condition, {}]
            merge_branches(merged_branches, branches_inside)
            memo[condition_key] = [condition_tuple, merged_branches]
          end
        end

        combined.values.to_h { |condition, branches| [condition, branches.values.to_h] }
      end

      def merge_branches(target, source)
        source.each do |branch, count|
          branch_key = tuple_identity(branch)
          branch_tuple, existing_count = target[branch_key]
          target[branch_key] = [branch_tuple || branch, existing_count ? existing_count + count : count]
        end
      end

      def tuple_identity(tuple)
        tuple = SourceFile::RubyDataParser.call(tuple)
        type, _id, start_line, start_column, end_line, end_column = tuple
        [type, start_line, start_column, end_line, end_column]
      end
    end
  end
end
