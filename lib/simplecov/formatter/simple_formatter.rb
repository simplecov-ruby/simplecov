# frozen_string_literal: true

module SimpleCov
  module Formatter
    class SimpleFormatter
      def format(result)
        criterion = SimpleCov.coverage_statistics_key(SimpleCov.primary_coverage)
        result.groups.map { |name, files| format_group(name, files, criterion) }.join
      end

    private

      def format_group(name, files, criterion)
        header = "Group: #{name}\n#{'=' * 40}\n"
        body = files.map do |file|
          "#{file.filename} (coverage: #{(_ = file.covered_percent(criterion)).floor(2)}%)\n"
        end.join
        "#{header}#{body}\n"
      end
    end
  end
end
