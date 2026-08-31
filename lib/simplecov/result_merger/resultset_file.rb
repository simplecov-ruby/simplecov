# frozen_string_literal: true

require "json"

module SimpleCov
  module ResultMerger
    # Read and parse a `.resultset.json` with the same tolerance the historical
    # `ResultMerger` had: a missing or empty file quietly returns `{}`, an
    # unparseable one warns and returns `{}`, and malformed entries inside a
    # valid file are warned about and dropped.
    module ResultsetFile
      extend self

      def parse(path)
        data = read(path)
        decode(data)
      end

      # A missing or blank file quietly means "no results yet"; anything else, a
      # 1-byte truncation included, flows through decode so corruption warns
      # instead of silently vanishing. Read first and rescue rather than check
      # exist?, which is racy against a concurrent clean.
      def read(path)
        data = File.read(path)
        return if data.match?(/\A\s*\z/)

        data
      rescue Errno::ENOENT
        nil
      end

      # Valid JSON need not be an object, but everything downstream iterates
      # command => data pairs, so anything else gets the same tolerance as a parse
      # failure. A "null" file has long meant an empty resultset.
      def decode(content)
        return {} unless content

        parsed = JSON.parse(content)
        return {} if parsed.nil?

        parsed.instance_of?(Hash) ? drop_malformed_entries(parsed) : invalid_resultset
      rescue StandardError
        invalid_resultset
      end

      def drop_malformed_entries(resultset)
        malformed, valid = resultset.partition { |_command_name, data| !well_formed_entry?(data) }
        return resultset if malformed.empty?

        warn "[SimpleCov]: Warning! Ignoring malformed resultset entries: #{malformed.map(&:first).sort.join(', ')}"
        valid.to_h
      end

      # Every consumer relies on a Hash carrying a Numeric "timestamp" and a Hash
      # "coverage". A truncated or hand-edited entry would otherwise crash out of
      # the middle of an at_exit merge.
      def well_formed_entry?(data)
        data.instance_of?(Hash) && data["timestamp"].is_a?(Numeric) && data["coverage"].instance_of?(Hash)
      end

      def invalid_resultset
        warn "[SimpleCov]: Warning! Parsing JSON content of resultset file failed"
        {}
      end
    end
  end
end
