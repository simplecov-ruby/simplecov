# frozen_string_literal: true

require_relative "json_formatter/result_hash_formatter"
require "json"
require "time"

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
        path = File.join(SimpleCov.coverage_path, FILENAME)
        warn_if_concurrent_overwrite(path)
        File.write(path, JSON.pretty_generate(self.class.build_hash(result)))
        puts output_message(result) unless @silent
      end

    private

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

      def output_message(result)
        "JSON Coverage report generated for #{result.command_name} to #{SimpleCov.coverage_path}. " \
          "#{result.covered_lines} / #{result.total_lines} LOC (#{result.covered_percent.round(2)}%) covered."
      end
    end
  end
end
