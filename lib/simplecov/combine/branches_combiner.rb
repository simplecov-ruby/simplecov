# frozen_string_literal: true

require_relative "../source_file/ruby_data_parser"
require_relative "identity_interner"
require_relative "interned_counts"

module SimpleCov
  module Combine
    module BranchesCombiner
      extend self

      def combine(coverage_a, coverage_b)
        merged = absorb({}, coverage_a) #: Hash[untyped, [untyped, Hash[untyped, untyped]]]
        materialize(absorb(merged, coverage_b))
      end

      # Folds `coverage` into `target`, an interned table keyed by condition
      # identity. Kept interned rather than turned back into tuple keys per merge,
      # so a fold over N resultsets interns each condition once instead of
      # re-interning the whole accumulated table N times.
      def absorb(target, coverage)
        return target unless coverage

        coverage.each do |condition, branches_inside|
          entry = target[identities[condition]] ||= new_condition(condition)
          InternedCounts.absorb_counts(entry.fetch(1), branches_inside, identities)
        end

        target
      end

      def new_condition(condition)
        arms = {} #: Hash[untyped, untyped]
        [condition, arms]
      end

      # Turns an interned table back into the tuple-keyed hash the rest of
      # SimpleCov reads. Done once, at the end of a fold.
      def materialize(target)
        target.values.to_h { |condition, branches| [condition, branches.values.to_h] }
      end

      def identities
        @identities ||= IdentityInterner.build { |tuple| tuple_identity(tuple) }
      end

      # Branches match on source span, whatever ids the recording processes handed
      # them (#1233).
      def tuple_identity(tuple)
        type, _id, start_line, start_column, end_line, end_column = SourceFile::RubyDataParser.call(tuple)
        [type, start_line, start_column, end_line, end_column].freeze
      end
    end
  end
end
