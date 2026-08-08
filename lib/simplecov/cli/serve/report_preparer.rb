# frozen_string_literal: true

require_relative "../../coverage_json"

module SimpleCov
  module CLI
    module Serve
      # Ensures the coverage directory has a renderable entry point before
      # the HTTP server binds. Existing self-contained reports take priority
      # over their optional JSON sidecar.
      module ReportPreparer
        def self.call(dir)
          index_path = File.join(dir, "index.html")
          json_path = File.join(dir, "coverage.json")
          return "#{dir} doesn't exist; run your test suite first" unless File.directory?(dir)
          return if File.file?(index_path)

          return "#{dir} has no index.html or coverage.json; run your test suite first" unless File.file?(json_path)

          require_relative "../../formatter/html_formatter"
          SimpleCov::Formatter::HTMLFormatter.new.format_from_json(json_path, dir)
          nil
        rescue SimpleCov::CoverageJSON::Error, SystemCallError => e
          "cannot build index.html from #{json_path}: #{e.message}"
        end
      end
    end
  end
end
