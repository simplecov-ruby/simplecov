# frozen_string_literal: true

require_relative "../source_file/ruby_data_parser"

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
      # Method coverage maps `[class, name, start_line, start_col, end_line,
      # end_col]` keys to hit counts. Keys are matched on their SOURCE
      # identity — (name, location), ignoring the class element — because
      # Ruby records one entry per receiver: the same `define_method` block
      # defined onto different classes in different processes arrives with
      # different (normalized) receivers for the same source method, and
      # matching on the full key would keep both, letting a never-called
      # receiver's 0 shadow a covered method after merge (issue #1234).
      # Combining sums the hit counts for matching methods and preserves
      # methods that only appear in one result.
      #
      # @return [Hash]
      #
      def combine(coverage_a, coverage_b)
        merged = {} #: Hash[untyped, [untyped, Integer]]
        [coverage_a, coverage_b].each_with_object(merged) do |coverage, memo|
          coverage.each do |key, count|
            method_key = source_identity(key)
            retained_key, existing = memo[method_key] || [key, 0]
            memo[method_key] = [retained_key, existing + count]
          end
        end

        merged.values.to_h
      end

      def source_identity(key)
        _class_name, *identity = SourceFile::RubyDataParser.call(key)
        identity
      end
    end
  end
end
