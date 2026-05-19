# frozen_string_literal: true

require_relative "base"
require "fileutils"
require "json"
require "time"

module SimpleCov
  module Formatter
    # Writes coverage results as JSON to coverage/coverage.json. Used
    # standalone, alongside the HTML formatter, or by external tools that
    # consume SimpleCov output.
    class JSONFormatter < Base
      FILENAME = "coverage.json"

      def self.build_hash(result)
        ResultHashFormatter.new(result).format
      end

      def format(result)
        FileUtils.mkdir_p(output_path)
        path = File.join(output_path, FILENAME)
        warn_if_concurrent_overwrite(path)
        File.write(path, JSON.pretty_generate(self.class.build_hash(result)))
        # stderr, not stdout: this is a status message, not the program's
        # output. Keeps the line out of pipelines like `rspec -f json`.
        warn output_message(result) unless @silent
      end

    private

      def message_prefix
        "JSON "
      end

      # Warns when the existing coverage.json has a timestamp newer than this
      # process's start time — a strong signal that a sibling test process
      # (e.g., parallel_tests) wrote it while we were running, and that our
      # write is about to clobber their data.
      def warn_if_concurrent_overwrite(path)
        start_time = SimpleCov.process_start_time or return
        existing_ts = existing_timestamp(path) or return
        return unless existing_ts > start_time

        warn "simplecov: #{path} was written at #{existing_ts.iso8601} — after " \
             "this process started at #{start_time.iso8601}. Overwriting " \
             "likely loses coverage data from a concurrent test run. For " \
             "parallel test setups, use SimpleCov::ResultMerger or run a single " \
             "collation step after all workers finish."
      end

      def existing_timestamp(path)
        return nil unless File.exist?(path)

        timestamp = JSON.parse(File.read(path), symbolize_names: true).dig(:meta, :timestamp)
        timestamp && Time.iso8601(timestamp)
      rescue JSON::ParserError, ArgumentError
        nil
      end
    end
  end
end

# Loaded after the JSONFormatter class is defined so the nested
# `class JSONFormatter` reopen inside result_hash_formatter.rb doesn't
# accidentally create a JSONFormatter < Object before this file gets a
# chance to declare `JSONFormatter < Base`.
require_relative "json_formatter/result_hash_formatter"
