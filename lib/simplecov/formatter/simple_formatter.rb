# frozen_string_literal: true

module SimpleCov
  module Formatter
    #
    # A ridiculously simple formatter for SimpleCov results.
    #
    class SimpleFormatter
      # Takes a SimpleCov::Result and generates a string out of it
      def format(result)
        result.groups.map { |name, files| format_group(name, files) }.join
      end

    private

      def format_group(name, files)
        header = "Group: #{name}\n#{'=' * 40}\n"
        # `covered_percent` is nilable across criteria, but line stats are
        # always measured, so the no-argument call can't return nil here.
        body   = files.map { |file| "#{file.filename} (coverage: #{(_ = file.covered_percent).floor(2)}%)\n" }.join
        "#{header}#{body}\n"
      end
    end
  end
end
