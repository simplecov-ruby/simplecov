# frozen_string_literal: true

require "json"
require "time"
require_relative "../atomic_file"

module SimpleCov
  module Formatter
    # Shared writer for the coverage.json artifact, used by JSONFormatter
    # (as its report) and HTMLFormatter (as the side file feeding
    # `simplecov serve` and external tools). Centralizing the write keeps
    # the two copies byte-identical (same pretty printing, same binary
    # mode, so no CRLF translation on Windows depending on which
    # formatter wrote last) and gives both formatters the
    # concurrent-overwrite warning of issue #1171.
    module CoverageJSONWriter
      FILENAME = "coverage.json"

      # The previous report can embed the project's entire source text,
      # so the overwrite check bounds how much of it is read looking for
      # the meta object before falling back to a full parse.
      META_SCAN_BYTES = 64 * 1024
      private_constant :META_SCAN_BYTES

      extend self

      def write(output_path, hash, result)
        path = File.join(output_path, FILENAME)
        warn_if_concurrent_overwrite(path, result)
        AtomicFile.write(path, JSON.pretty_generate(hash), binary: true)
        path
      end

      # Warns when the existing coverage.json has a timestamp newer than this
      # process's start time — a strong signal that a sibling test process
      # (e.g., parallel_tests) wrote it while we were running, and that our
      # write is about to clobber their data.
      def warn_if_concurrent_overwrite(path, result)
        start_time = SimpleCov.process_start_time or return
        existing = existing_meta(path) or return
        return unless existing.fetch(:timestamp) > start_time

        # Both formatters write coverage.json through this method, so when
        # they are configured together the file found here was just written
        # by our own run, not a concurrent one. A matching command_name
        # means the same merged result, so there's nothing to lose by
        # overwriting. See issue #1171.
        return if existing.fetch(:command_name).eql?(result.command_name)

        warn "simplecov: #{path} was written at #{existing[:timestamp].iso8601} — after " \
             "this process started at #{start_time.iso8601}. Overwriting " \
             "likely loses coverage data from a concurrent test run. For " \
             "parallel test setups, use SimpleCov::ResultMerger or run a single " \
             "collation step after all workers finish."
      end

      def existing_meta(path)
        return nil unless File.exist?(path)

        meta = parse_meta(path) or return nil
        timestamp = parse_time(meta[:timestamp]) or return nil

        {timestamp: timestamp, command_name: meta[:command_name]}
      end

      # Our own writer emits an ISO 8601 string, but coverage.json is
      # whatever wrote it last: third-party formatters (undercover's
      # among them) rewrite it in their own shape with an epoch integer
      # in meta.timestamp, and Time.iso8601 raised TypeError on that,
      # taking the whole report down on the next run. Both spellings
      # feed the concurrency check; anything else disables it for this
      # file instead of failing the write. See #1285.
      def parse_time(value)
        case value
        when String then Time.iso8601(value)
        when Numeric then Time.at(value)
        end
      rescue ArgumentError
        nil
      end

      def parse_meta(path)
        parse_meta_head(path) || parse_meta_full(path)
      end

      # The meta object is flat and sits at the head of every file this
      # module writes, so the common case parses just that slice instead
      # of a multi-megabyte report. A miss (foreign key order, a brace
      # inside a meta string) falls back to the full parse.
      def parse_meta_head(path)
        head = File.read(path, META_SCAN_BYTES).to_s
        slice = head[/"meta"\s*:\s*(\{.*?\})/m, 1]
        return nil unless slice

        # The captured slice is always a JSON object, so a successful parse
        # is always a Hash.
        JSON.parse(slice, symbolize_names: true)
      rescue JSON::ParserError
        nil
      end

      def parse_meta_full(path)
        parsed = JSON.parse(File.read(path), symbolize_names: true)
        parsed[:meta] if parsed.is_a?(Hash)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
