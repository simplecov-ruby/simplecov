# frozen_string_literal: true

require_relative "../source_file/ruby_data_parser"
require_relative "identity_interner"

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
        [coverage_a, coverage_b].each do |coverage|
          coverage.each do |condition, branches_inside|
            entry = merged[identities[condition]] ||= [condition, {}]
            merge_branches(entry[1], branches_inside)
          end
        end

        merged.values.to_h { |condition, branches| [condition, branches.values.to_h] }
      end

      # `target` and its pairs are always built by `combine` above, so updating
      # them in place can't reach data a caller still holds.
      def merge_branches(target, source)
        source.each do |branch, count|
          branch_key = identities[branch]
          existing = target[branch_key]
          if existing
            existing[1] += count
          else
            target[branch_key] = [branch, count]
          end
        end
      end

      # Bounded by the project's branch count, like `RubyDataParser`'s parse
      # cache.
      def identities
        @identities ||= IdentityInterner.build { |tuple| tuple_identity(tuple) }
      end

      # Branches match on source span, whatever ids the recording processes
      # handed them (issue #1233).
      def tuple_identity(tuple)
        type, _id, start_line, start_column, end_line, end_column = SourceFile::RubyDataParser.call(tuple)
        [type, start_line, start_column, end_line, end_column].freeze
      end
    end
  end
end
