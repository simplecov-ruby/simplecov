# frozen_string_literal: true

module SimpleCov
  module Formatter
    #
    # A ridiculously simple formatter for SimpleCov results.
    #
    class SimpleFormatter
      # Takes a SimpleCov::Result and generates a string out of it
      def format(result)
        criterion = SimpleCov.coverage_statistics_key(SimpleCov.primary_coverage)
        result.groups.map { |name, files| format_group(name, files, criterion) }.join
      end

    private

      def format_group(name, files, criterion)
        header = "Group: #{name}\n#{'=' * 40}\n"
        # The configured primary criterion is enabled, so every result file
        # carries its corresponding statistic despite the nilable public API.
        body = files.map do |file|
          "#{file.filename} (coverage: #{(_ = file.covered_percent(criterion)).floor(2)}%)\n"
        end.join
        "#{header}#{body}\n"
      end
    end
  end
end
