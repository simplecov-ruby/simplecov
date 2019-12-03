# frozen_string_literal: true

module SimpleCov
  # There might be reports from different kinds of tests,
  # e.g. RSpec and Cucumber. We need to combine their results
  # into unified one. This class does that.
  # To unite the results on file basis, it leverages
  # the combiners of lines and branches inside each file within given results.
  class RunResultsCombiner
    attr_reader :results

    def self.combine!(*results)
      new(*results).call
    end

    def initialize(*results)
      @results = results
    end

    #
    # Combine process explanation
    # => ResultCombiner: define all present files between results and start combine on file level.
    # ==> FileCombiner: collect result of next combine levels lines and branches.
    # ===> LinesCombiner: combine lines results.
    # ===> BranchesCombiner: combine branches results.
    #
    # @return [Hash]
    #
    def call
      results.reduce({}) do |result, next_result|
        combine_result_sets(result, next_result)
      end
    end

    #
    # Manage combining results on files level
    #
    # @param [Hash] first_result
    # @param [Hash] second_result
    #
    # @return [Hash]
    #
    def combine_result_sets(first_result, second_result)
      results_files = first_result.keys | second_result.keys

      results_files.each_with_object({}) do |file_name, combined_results|
        combined_results[file_name] = combine_file_coverage(
          first_result[file_name],
          second_result[file_name]
        )
      end
    end

    #
    # Combine two files coverage results
    #
    # @param [Hash] first_coverage
    # @param [Hash] second_coverage
    #
    # @return [Hash]
    #
    def combine_file_coverage(first_coverage, second_coverage)
      SimpleCov::Combiners::FilesCombiner.combine!(first_coverage, second_coverage)
    end
  end
end
