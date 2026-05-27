# frozen_string_literal: true

module SimpleCov
  module ResultMerger
    # We changed the format of the raw result data in simplecov, as people
    # are likely to have "old" resultsets lying around (but not too old so
    # that they're still considered we can adapt them). See
    # https://github.com/simplecov-ruby/simplecov/pull/824#issuecomment-576049747
    module LegacyFormatAdapter
    module_function

      def call(result)
        pre_0_18?(result) ? upgrade(result) : result
      end

      # Pre-0.18 coverage data pointed from file directly to an array of
      # line coverage rather than a `{"lines" => [...]}` hash.
      def pre_0_18?(result)
        _key, data = result.first
        data.is_a?(Array)
      end

      def upgrade(result)
        result.transform_values { |line_coverage_data| {"lines" => line_coverage_data} }
      end
    end
  end
end
