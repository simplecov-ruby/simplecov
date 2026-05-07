# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "json_formatter"

module SimpleCov
  module Formatter
    # Generates an HTML coverage report by writing a coverage_data.js file
    # alongside pre-compiled static assets (index.html, application.js/css).
    # Uses JSONFormatter.build_hash to serialize the result, then writes both
    # coverage.json and coverage_data.js from the same in-memory hash.
    class HTMLFormatter
      DATA_FILENAME = "coverage_data.js"

      # `output_dir` defaults to `SimpleCov.coverage_path` so the at_exit
      # pipeline keeps working unchanged. Pass it explicitly to write
      # somewhere else (handy for tests that don't want to clobber
      # the project's `coverage/` directory).
      def initialize(silent: false, output_dir: nil)
        @silent = silent
        @output_dir = output_dir
      end

      def format(result)
        json = JSON.pretty_generate(JSONFormatter.build_hash(result))

        FileUtils.mkdir_p(output_path)
        File.write(File.join(output_path, JSONFormatter::FILENAME), json)
        File.write(File.join(output_path, DATA_FILENAME), "window.SIMPLECOV_DATA = #{json};\n", mode: "wb")

        copy_static_assets
        puts output_message(result) unless @silent
      end

      # Generate HTML from a pre-existing coverage.json file without
      # needing a live SimpleCov::Result or even a running test suite.
      def format_from_json(json_path, output_dir)
        FileUtils.mkdir_p(output_dir)
        json = File.read(json_path)
        File.write(File.join(output_dir, DATA_FILENAME), "window.SIMPLECOV_DATA = #{json};\n", mode: "wb")
        copy_static_assets(output_dir)
      end

    private

      def copy_static_assets(dest_dir = output_path)
        # Copy via temp file + atomic rename so parallel test workers writing
        # to the same coverage directory don't race on the unlink step.
        Dir[File.join(public_dir, "*")].each do |src|
          dest = File.join(dest_dir, File.basename(src))
          temp = "#{dest}.#{Process.pid}.#{rand(2**32).to_s(36)}"
          begin
            FileUtils.cp(src, temp)
            File.rename(temp, dest)
          ensure
            FileUtils.rm_f(temp)
          end
        end
      end

      def output_message(result)
        "Coverage report generated for #{result.command_name} to #{output_path}. " \
          "#{result.covered_lines} / #{result.total_lines} LOC (#{result.covered_percent.round(2)}%) covered."
      end

      def output_path
        @output_dir || SimpleCov.coverage_path
      end

      def public_dir
        File.join(__dir__, "html_formatter/public/")
      end
    end
  end
end
