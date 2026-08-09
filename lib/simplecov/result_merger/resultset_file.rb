# frozen_string_literal: true

require "json"

module SimpleCov
  module ResultMerger
    # Read + parse a `.resultset.json` file with the same tolerance the
    # historical `ResultMerger` had: a missing or empty file quietly
    # returns `{}`, an unparseable one warns and returns `{}`, and parse
    # success returns the decoded Hash with any malformed entries
    # warned about and dropped.
    module ResultsetFile
    module_function

      def parse(path)
        data = read(path)
        decode(data)
      end

      def read(path)
        return unless File.exist?(path)

        data = File.read(path)
        return if data.nil? || data.length < 2

        data
      end

      def decode(content)
        return {} unless content

        parsed = JSON.parse(content)
        return {} if parsed.nil? # a "null" file has long meant an empty resultset

        # Valid JSON need not be an object ("[1,2]" and "\"x\"" parse
        # fine), but everything downstream iterates command => data
        # pairs, so anything else would crash out of the middle of a
        # merge. Same tolerance as a parse failure: warn and move on.
        parsed.is_a?(Hash) ? drop_malformed_entries(parsed) : invalid_resultset
      rescue StandardError
        invalid_resultset
      end

      # Each surviving entry must have the shape every consumer relies
      # on: a Hash carrying a Numeric "timestamp" (the merge-timeout
      # check) and a Hash "coverage" (the merge fold). A truncated or
      # hand-edited entry would otherwise crash out of the middle of an
      # at_exit merge, so it gets the same warn-and-move-on treatment
      # as an unparseable file.
      def drop_malformed_entries(resultset)
        malformed, valid = resultset.partition { |_command_name, data| !well_formed_entry?(data) }
        return resultset if malformed.empty?

        warn "[SimpleCov]: Warning! Ignoring malformed resultset entries: #{malformed.map(&:first).sort.join(', ')}"
        valid.to_h
      end

      def well_formed_entry?(data)
        data.is_a?(Hash) && data["timestamp"].is_a?(Numeric) && data["coverage"].is_a?(Hash)
      end

      def invalid_resultset
        warn "[SimpleCov]: Warning! Parsing JSON content of resultset file failed"
        {}
      end
    end
  end
end
