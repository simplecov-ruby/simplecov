# frozen_string_literal: true

require_relative "json_formatter/result_hash_formatter"
require "json"

module SimpleCov
  module Formatter
    class JSONFormatter
      FILENAME = "coverage.json"

      def initialize(silent: false)
        @silent = silent
      end

      def self.build_hash(result)
        ResultHashFormatter.new(result).format
      end

      def format(result)
        json = JSON.pretty_generate(self.class.build_hash(result))
        File.write(File.join(SimpleCov.coverage_path, FILENAME), json)
        puts output_message(result) unless @silent
      end

    private

      def output_message(result)
        "JSON Coverage report generated for #{result.command_name} to #{SimpleCov.coverage_path}. " \
          "#{result.covered_lines} / #{result.total_lines} LOC (#{result.covered_percent.round(2)}%) covered."
      end
    end
  end
end
