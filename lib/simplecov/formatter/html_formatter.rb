# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "base"
require_relative "json_formatter"

module SimpleCov
  module Formatter
    # Generates an HTML coverage report by writing a coverage_data.js file
    # alongside pre-compiled static assets (index.html, application.js/css).
    # Uses JSONFormatter.build_hash to serialize the result, then writes both
    # coverage.json and coverage_data.js from the same in-memory hash.
    class HTMLFormatter < Base
      DATA_FILENAME = "coverage_data.js"

      def format(result)
        # `coverage_data.js` feeds the client-side viewer, which renders
        # source from the embedded array — it always needs `source`,
        # regardless of `SimpleCov.source_in_json`. The side-file
        # `coverage.json` honors the setting so downstream tools that
        # read source from disk can opt into a smaller payload. When
        # the setting is at its default (true), the two files share a
        # single serialization.
        FileUtils.mkdir_p(output_path)
        viewer_json = JSON.pretty_generate(JSONFormatter.build_hash(result, include_source: true))
        coverage_json = SimpleCov.source_in_json ? viewer_json : JSON.pretty_generate(JSONFormatter.build_hash(result))

        atomic_write(File.join(output_path, JSONFormatter::FILENAME), coverage_json)
        atomic_write(File.join(output_path, DATA_FILENAME), "window.SIMPLECOV_DATA = #{viewer_json};\n")

        copy_static_assets
        # stderr, not stdout: this is a status message, not the program's
        # output. Keeps the line out of pipelines like `rspec -f json`.
        $stderr.puts output_message(result) unless @silent # rubocop:disable Style/StderrPuts
      end

      # Generate HTML from a pre-existing coverage.json file without
      # needing a live SimpleCov::Result or even a running test suite.
      def format_from_json(json_path, output_dir)
        FileUtils.mkdir_p(output_dir)
        json = File.read(json_path)
        atomic_write(File.join(output_dir, DATA_FILENAME), "window.SIMPLECOV_DATA = #{json};\n")
        copy_static_assets(output_dir)
      end

    private

      def entry_point_filename
        "index.html"
      end

      def copy_static_assets(dest_dir = output_path)
        Dir[File.join(public_dir, "*")].each do |src|
          atomic_write(File.join(dest_dir, File.basename(src)), File.binread(src))
        end
      end

      # Write `content` at `dest` via a uniquely-named temp file in the
      # same directory, then `File.rename` onto the final path. rename is
      # atomic and overwrite-safe, so:
      # - parallel writers can't race on an unlink-then-write window, and
      # - read-only existing files (e.g. assets shipped at 0444 from
      #   /nix/store) are replaced cleanly instead of triggering EACCES
      #   from opening the existing path for writing.
      def atomic_write(dest, content)
        temp = "#{dest}.#{Process.pid}.#{rand(2**32).to_s(36)}"
        begin
          File.binwrite(temp, content)
          File.rename(temp, dest)
        ensure
          FileUtils.rm_f(temp)
        end
      end

      def public_dir
        # `.to_s` collapses `__dir__`'s nil arm (only possible under eval,
        # which can't happen for a file on disk) so the path is a String.
        File.join(__dir__.to_s, "html_formatter/public/")
      end
    end
  end
end
