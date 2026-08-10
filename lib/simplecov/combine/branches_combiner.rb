# frozen_string_literal: true

require_relative "../source_file/ruby_data_parser"
require_relative "identity_interner"
require_relative "interned_counts"

module SimpleCov
  module Combine
    #
    # Combine different branch coverage results on single file.
    #
    # Should be called through `CoverageAccumulator`.
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
        merged = absorb({}, coverage_a) #: Hash[untyped, [untyped, Hash[untyped, untyped]]]
        materialize(absorb(merged, coverage_b))
      end

      # Folds `coverage` into `target`, an interned table keyed by condition
      # identity. Kept interned (rather than turned back into tuple keys per
      # merge) so a fold over N resultsets interns each condition once
      # instead of re-interning the whole accumulated table N times.
      #
      # @return [Hash] `target`
      def absorb(target, coverage)
        return target unless coverage

        coverage.each do |condition, branches_inside|
          entry = target[identities[condition]] ||= new_condition(condition)
          InternedCounts.absorb_counts(entry[1], branches_inside, identities)
        end

        target
      end

      # Split out so the empty arm table has somewhere to carry its type
      # annotation. Only allocated the first time a condition is seen.
      def new_condition(condition)
        arms = {} #: Hash[untyped, untyped]
        [condition, arms]
      end

      # Turns an interned table back into the tuple-keyed hash the rest of
      # SimpleCov reads. Done once, at the end of a fold.
      #
      # @return [Hash]
      def materialize(target)
        target.values.to_h { |condition, branches| [condition, branches.values.to_h] }
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
