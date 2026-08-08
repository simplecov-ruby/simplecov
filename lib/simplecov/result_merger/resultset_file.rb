# frozen_string_literal: true

require "json"

module SimpleCov
  module ResultMerger
    # Read + parse a `.resultset.json` file with the same tolerance the
    # historical `ResultMerger` had: missing file returns `{}`, an empty
    # or unparseable file warns and returns `{}`, parse success returns
    # the decoded Hash.
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
        parsed.is_a?(Hash) ? parsed : invalid_resultset
      rescue StandardError
        invalid_resultset
      end

      def invalid_resultset
        warn "[SimpleCov]: Warning! Parsing JSON content of resultset file failed"
        {}
      end
    end
  end
end
