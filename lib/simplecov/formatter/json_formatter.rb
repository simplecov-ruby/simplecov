# frozen_string_literal: true

require_relative "base"
require_relative "coverage_json_writer"
require "json"

module SimpleCov
  module Formatter
    class JSONFormatter < Base
      FILENAME = CoverageJSONWriter::FILENAME

      # Callers that need the source array regardless of the global setting (the
      # HTML formatter, which feeds the client-side viewer) pass
      # `include_source: true` explicitly.
      def self.build_hash(result, include_source: SimpleCov.source_in_json)
        ResultHashFormatter.format(result, include_source: include_source)
      end

      def format(result)
        CoverageJSONWriter.write(output_path, self.class.build_hash(result), result)
        emit_status(result)
      end

      private

      def message_prefix
        "JSON "
      end

      def entry_point_filename
        FILENAME
      end
    end
  end
end

# Loaded after the JSONFormatter class is defined so the nested reopen inside
# result_hash_formatter.rb doesn't create a JSONFormatter < Object before this
# file gets a chance to declare `JSONFormatter < Base`.
require_relative "json_formatter/result_hash_formatter"
