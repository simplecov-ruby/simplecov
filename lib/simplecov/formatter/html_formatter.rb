# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "base"
require_relative "../atomic_file"
require_relative "../coverage_json"
require_relative "json_formatter"

module SimpleCov
  module Formatter
    # Generates a single self-contained HTML coverage report. The compiled
    # template already carries the viewer app's JS and CSS inline, so the report
    # can be mailed, uploaded as one CI artifact, or opened from anywhere
    # without sibling files. A coverage.json is written alongside from the same
    # in-memory hash.
    class HTMLFormatter < Base
      DATA_MARKER = "<!-- SIMPLECOV_COVERAGE_DATA -->"

      LEGACY_REPORT_FILES = %w[
        coverage_data.js application.js application.css
        favicon_green.png favicon_red.png favicon_yellow.png
      ].freeze

      def format(result)
        viewer_hash = JSONFormatter.build_hash(result, include_source: true)
        json_hash = SimpleCov.source_in_json ? viewer_hash : source_less_hash(viewer_hash)
        write_report_files(json_hash, viewer_hash, result)
        emit_status(result)
      end

      # Generates HTML from a pre-existing coverage.json without a live Result or
      # even a running test suite. The round-trip through parse/generate compacts
      # the input and rejects invalid JSON here rather than at view time.
      def format_from_json(json_path, output_dir)
        data = ViewerDataValidator.call(CoverageJSON.load(json_path))
        json = JSON.generate(data)
        AtomicFile.write(File.join(output_dir, "index.html"), render_report(json), binary: true)
      end

    private

      def entry_point_filename
        "index.html"
      end

      # The inlined report data feeds the client-side viewer, which renders source
      # from the embedded array, so it always needs `source` regardless of
      # `SimpleCov.source_in_json`. The side-file `coverage.json` honors the
      # setting, and stays pretty-printed for human readers while the embedded
      # copy is serialized compactly.
      def source_less_hash(hash)
        coverage = hash.fetch(:coverage).transform_values { |file| file.except(:source) }
        hash.merge(coverage: coverage)
      end

      def write_report_files(json_hash, viewer_hash, result)
        CoverageJSONWriter.write(output_path, json_hash, result)
        AtomicFile.write(File.join(output_path, "index.html"), render_report(JSON.generate(viewer_hash)), binary: true)
        FileUtils.rm_f(LEGACY_REPORT_FILES.map { |name| File.join(output_path, name) })
      end

      # `<` is escaped as \u003c, valid JSON since `<` can only occur inside
      # strings, so embedded source text containing "</script>" cannot terminate
      # the surrounding element. Block forms keep gsub/sub from interpreting
      # backslashes in the JSON as replacement-string back-references.
      #
      # The template is read as UTF-8 explicitly, not the locale's
      # `Encoding.default_external`: substituting a UTF-8 payload into a template
      # tagged US-ASCII raises Encoding::CompatibilityError.
      def render_report(json)
        template = File.read(File.join(public_dir, "index.html"), encoding: Encoding::UTF_8)
        unless template.include?(DATA_MARKER)
          raise "SimpleCov's HTML template is missing its #{DATA_MARKER.inspect} marker"
        end

        data_script = "<script>window.SIMPLECOV_DATA = #{json.gsub('<') { '\u003c' }};</script>"
        template.sub(DATA_MARKER) { data_script }
      end

      def public_dir
        "#{__dir__}/html_formatter/public/"
      end
    end
  end
end

require_relative "html_formatter/viewer_data_validator"
