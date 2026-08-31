# frozen_string_literal: true

require_relative "coverage_accumulator"

module SimpleCov
  module Combine
    module ResultsCombiner
      extend self

      # Callers that read their results one at a time, to keep a big CI run's
      # resultsets out of memory at once, should drive a `CoverageAccumulator`
      # directly instead of collecting the results to pass here.
      def combine(*results)
        accumulator = CoverageAccumulator.new
        results.each { |result| accumulator.absorb(result) }
        accumulator.result || {}
      end
    end
  end
end
