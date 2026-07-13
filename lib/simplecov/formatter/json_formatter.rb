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

      # `include_source:` defaults to `SimpleCov.source_in_json` (true
      # by default) so the historical payload shape is unchanged.
      # Callers that need the source array regardless of the global
      # setting (the HTML formatter, which feeds the client-side
      # viewer) pass `include_source: true` explicitly.
      def self.build_hash(result, include_source: SimpleCov.source_in_json)
        ResultHashFormatter.new(result, include_source: include_source).format
      end

      def format(result)
        FileUtils.mkdir_p(output_path)
        path = File.join(output_path, FILENAME)
        warn_if_concurrent_overwrite(path, result)
        File.write(path, JSON.pretty_generate(self.class.build_hash(result)))
        # stderr, not stdout: this is a status message, not the program's
        # output. Keeps the line out of pipelines like `rspec -f json`.
        $stderr.puts output_message(result) unless @silent # rubocop:disable Style/StderrPuts
      end

    private

      def message_prefix
        "JSON "
      end

      def entry_point_filename
        FILENAME
      end

      # Warns when the existing coverage.json has a timestamp newer than this
      # process's start time — a strong signal that a sibling test process
      # (e.g., parallel_tests) wrote it while we were running, and that our
      # write is about to clobber their data.
      def warn_if_concurrent_overwrite(path, result)
        start_time = SimpleCov.process_start_time or return
        existing = existing_meta(path) or return
        return unless existing[:timestamp] > start_time

        # The HTML formatter also writes coverage.json (it shares the file as
        # a side artifact), so when both formatters are configured the file we
        # find was just written by our own run, not a concurrent one. A
        # matching command_name means the same merged result, so there's
        # nothing to lose by overwriting. See issue #1171.
        return if existing[:command_name] == result.command_name

        warn "simplecov: #{path} was written at #{existing[:timestamp].iso8601} — after " \
             "this process started at #{start_time.iso8601}. Overwriting " \
             "likely loses coverage data from a concurrent test run. For " \
             "parallel test setups, use SimpleCov::ResultMerger or run a single " \
             "collation step after all workers finish."
      end

      def existing_meta(path)
        return nil unless File.exist?(path)

        meta = JSON.parse(File.read(path), symbolize_names: true)
        timestamp = meta.dig(:meta, :timestamp)
        return nil unless timestamp

        {timestamp: Time.iso8601(timestamp), command_name: meta.dig(:meta, :command_name)}
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
