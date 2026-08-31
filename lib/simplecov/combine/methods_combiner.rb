# frozen_string_literal: true

require_relative "../source_file/ruby_data_parser"
require_relative "identity_interner"
require_relative "interned_counts"

module SimpleCov
  module Combine
    module MethodsCombiner
      extend self

      # Method coverage maps `[class, name, start_line, start_col, end_line,
      # end_col]` keys to hit counts. Keys are matched on their source identity,
      # the location alone, because Ruby records one entry per defined method: the
      # same `define_method` block defined onto different classes, or under
      # different names, in different processes arrives with different receivers
      # for the same source method, and matching on the full key would keep both,
      # letting a never-called copy's 0 shadow a covered method (#1234).
      def combine(coverage_a, coverage_b)
        merged = absorb({}, coverage_a) #: Hash[untyped, [untyped, Integer]]
        materialize(absorb(merged, coverage_b))
      end

      # A `nil` `target` stays `nil` until some resultset actually carries
      # methods, so a merge can tell "no method data anywhere" apart from "method
      # data that covers nothing".
      def absorb(target, coverage)
        return target unless coverage

        target ||= {} #: Hash[untyped, [untyped, Integer]]
        InternedCounts.absorb_counts(target, coverage, identities)
      end

      def materialize(target)
        target.values.to_h
      end

      def identities
        @identities ||= IdentityInterner.build { |key| source_identity(key) }
      end

      def source_identity(key)
        _class_name, _method_name, *location = SourceFile::RubyDataParser.call(key)
        location.freeze
      end
    end
  end
end
