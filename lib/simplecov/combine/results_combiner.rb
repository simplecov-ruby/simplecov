# frozen_string_literal: true

module SimpleCov
  module Combine
    # There might be reports from different kinds of tests,
    # e.g. RSpec and Cucumber. We need to combine their results
    # into unified one. This class does that.
    # To unite the results on file basis, it leverages
    # the combine of lines and branches inside each file within given results.
    module ResultsCombiner
    module_function

      #
      # Combine process explanation
      # => ResultCombiner: define all present files between results and start combine on file level.
      # ==> FileCombiner: collect result of next combine levels lines and branches.
      # ===> LinesCombiner: combine lines results.
      # ===> BranchesCombiner: combine branches results.
      #
      # @return [Hash]
      #
      def combine(*results)
        results.reduce({}) do |combined_results, next_result|
          combine_result_sets(combined_results, next_result)
        end
      end

      #
      # Manage combining results on files level
      #
      # @param [Hash] result_a
      # @param [Hash] result_b
      #
      # @return [Hash]
      #
      def combine_result_sets(combined_results, result)
        unless correct_format?(result)
          warn_wrong_format
          return combined_results
        end

        results_files = combined_results.keys | result.keys

        results_files.each_with_object({}) do |file_name, file_combination|
          file_combination[file_name] = combine_file_coverage(
            combined_results[file_name],
            result[file_name]
          )
        end
      end

      # We might start a run of a new simplecov version with a new format stored while
      # there is still a recent file like this lying around. If it's recent enough (
      # see merge_timeout) it will end up here. In order not to crash against this
      # we need to do some basic checking of the format of data we expect and
      # otherwise ignore it. See #820
      #
      # Currently correct format is:
      # { symbol_file_path => {coverage_criterion => coverage_date}}
      #
      # Internal use/reliance only.
      def correct_format?(result)
        result.empty? || matches_current_format?(result)
      end

      def matches_current_format?(result)
        # I so wish I could already use pattern matching
        key, data = result.first

        key.is_a?(Symbol) && second_level_choice_of_criterion?(data)
      end

      SECOND_LEVEL_KEYS = %i[lines branches].freeze
      def second_level_choice_of_criterion?(data)
        second_level_key, = data.first

        SECOND_LEVEL_KEYS.member?(second_level_key)
      end

      def warn_wrong_format
        warn "Merging results, encountered an incorrectly formatted value. "\
          "This value was ignored.\nIf you just upgraded simplecov this is "\
          "likely due to a changed file format. If this happens again please "\
          "file a bug. https://github.com/colszowka/simplecov/issues"
      end

      #
      # Combine two files coverage results
      #
      # @param [Hash] coverage_a
      # @param [Hash] coverage_b
      #
      # @return [Hash]
      #
      def combine_file_coverage(coverage_a, coverage_b)
        Combine.combine(Combine::FilesCombiner, coverage_a, coverage_b)
      end
    end
  end
end
