# frozen_string_literal: true

module SimpleCov
  module ResultMerger
    module LegacyFormatAdapter
      extend self

      def call(result)
        pre_0_18?(result) ? upgrade(result) : result
      end

      # Pre-0.18 coverage data pointed from file directly to an array of line
      # coverage rather than a `{"lines" => [...]}` hash.
      def pre_0_18?(result)
        _key, data = result.first
        data.instance_of?(Array)
      end

      def upgrade(result)
        result.transform_values { |line_coverage_data| {"lines" => line_coverage_data} }
      end
    end
  end
end
