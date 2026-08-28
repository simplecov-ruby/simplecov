# frozen_string_literal: true

require_relative "coverage_accumulator"

module SimpleCov
  module Combine
    # There might be reports from different kinds of tests,
    # e.g. RSpec and Cucumber. We need to combine their results
    # into unified one. This class does that.
    # To unite the results on file basis, it leverages
    # the combine of lines and branches inside each file within given results.
    module ResultsCombiner
      extend self

      #
      # Combine process explanation
      # => ResultsCombiner: hand every result to one accumulator.
      # ==> CoverageAccumulator::MergedFile: hold one file's merged coverage.
      # ===> LinesCombiner: combine lines results.
      # ===> BranchesCombiner: combine branches results.
      # ===> MethodsCombiner: combine methods results.
      #
      # Callers that read their results one at a time (`ResultMerger`, to
      # keep a big CI run's resultsets out of memory all at once) should
      # drive a `CoverageAccumulator` directly instead of collecting the
      # results to pass here.
      #
      # @return [Hash]
      #
      def combine(*results)
        accumulator = CoverageAccumulator.new
        results.each { |result| accumulator.absorb(result) }
        accumulator.result || {}
      end
    end
  end
end
