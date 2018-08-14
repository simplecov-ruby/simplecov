# frozen_string_literal: true

#
# A ridiculously simple formatter for SimpleCov results.
#
module SimpleCov
  module Formatter
    class SimpleFormatter
      # Takes a SimpleCov::Result and generates a string out of it
      def format(result)
        output = "".dup
        output << "Coverage Output\n"
        output << "=" * 40
        output << "\n"
        result.source_files.each do |file|
          output << "#{File.basename file.filename} (coverage: #{file.covered_percent.round(2)}%)\n"
        end
        output << "\n"
        puts output
        output
      end
    end
  end
end
