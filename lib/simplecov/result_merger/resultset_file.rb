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

        JSON.parse(content) || {}
      rescue StandardError
        warn "[SimpleCov]: Warning! Parsing JSON content of resultset file failed"
        {}
      end
    end
  end
end
