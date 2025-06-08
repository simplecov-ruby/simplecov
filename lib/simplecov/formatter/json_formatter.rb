# frozen_string_literal: true

require_relative "json_formatter/result_hash_formatter"
require_relative "json_formatter/result_exporter"
require "json"

module SimpleCov
  module Formatter
    class JSONFormatter
      def format(result, verbose: true)
        result_hash = format_result(result)

        export_formatted_result(result_hash)

        puts output_message(result) if verbose
      end

    private

      def format_result(result)
        result_hash_formater = ResultHashFormatter.new(result)
        result_hash_formater.format
      end

      def export_formatted_result(result_hash)
        result_exporter = ResultExporter.new(result_hash)
        result_exporter.export
      end

      def output_message(result)
        "JSON Coverage report generated for #{result.command_name} to #{SimpleCov.coverage_path}. " \
          "#{result.covered_lines} / #{result.total_lines} LOC (#{result.covered_percent.round(2)}%) covered."
      end
    end
  end
end
