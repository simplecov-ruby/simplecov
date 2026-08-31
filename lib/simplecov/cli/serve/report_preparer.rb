# frozen_string_literal: true

require_relative "../../coverage_json"

module SimpleCov
  module CLI
    module Serve
      module ReportPreparer
        def self.call(dir)
          index_path = File.join(dir, "index.html")
          json_path = File.join(dir, "coverage.json")
          return "#{dir} doesn't exist; run your test suite first" unless File.directory?(dir)
          return if File.file?(index_path)

          return "#{dir} has no index.html or coverage.json; run your test suite first" unless File.file?(json_path)

          build_index(json_path, dir)
        rescue CoverageJSON::Error, SystemCallError => e
          "cannot build index.html from #{json_path}: #{e}"
        end

        def self.build_index(json_path, dir)
          require_relative "../../formatter/html_formatter"
          Formatter::HTMLFormatter.new.format_from_json(json_path, dir)
          nil
        end
      end
    end
  end
end
