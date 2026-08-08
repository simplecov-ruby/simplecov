# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "base"
require_relative "json_formatter"

module SimpleCov
  module Formatter
    # Generates a single self-contained HTML coverage report. The compiled
    # template (public/index.html) already carries the viewer app's JS and
    # CSS inline; format substitutes the coverage JSON at the data marker
    # and writes one index.html, so the report can be mailed, uploaded as
    # a single CI artifact, or opened from anywhere without sibling files.
    # A coverage.json is written alongside from the same in-memory hash.
    class HTMLFormatter < Base
      # Placeholder in the compiled template where the report's data goes.
      DATA_MARKER = "<!-- SIMPLECOV_COVERAGE_DATA -->"

      # The sibling files a 1.0.0 through 1.0.3 report wrote next to
      # index.html. They are stale the moment a single-file report lands
      # on top of them — `simplecov serve` would happily keep serving the
      # old coverage_data.js — so formatting removes the known names.
      LEGACY_REPORT_FILES = %w[
        coverage_data.js application.js application.css
        favicon_green.png favicon_red.png favicon_yellow.png
      ].freeze

      def format(result)
        # The inlined report data feeds the client-side viewer, which
        # renders source from the embedded array — it always needs
        # `source`, regardless of `SimpleCov.source_in_json`. The
        # side-file `coverage.json` honors the setting so downstream
        # tools that read source from disk can opt into a smaller
        # payload. The embedded copy is serialized compactly (pretty
        # printing puts every element of every per-line coverage array
        # on its own indented line, roughly doubling the payload);
        # coverage.json stays pretty-printed for human readers.
        FileUtils.mkdir_p(output_path)
        viewer_hash = JSONFormatter.build_hash(result, include_source: true)
        json_hash = SimpleCov.source_in_json ? viewer_hash : JSONFormatter.build_hash(result)
        write_report_files(json_hash, viewer_hash)
        emit_status(result)
      end

      # Generate HTML from a pre-existing coverage.json file without
      # needing a live SimpleCov::Result or even a running test suite.
      # The round-trip through parse/generate compacts the (typically
      # pretty-printed) input and rejects invalid JSON here rather than
      # embedding it and failing at view time.
      def format_from_json(json_path, output_dir)
        FileUtils.mkdir_p(output_dir)
        # UTF-8 explicitly (JSON is UTF-8 by definition): `File.read`
        # would tag the text with `Encoding.default_external`, and a
        # non-UTF-8 locale (minimal CI containers resolve to US-ASCII,
        # Windows to a code page) would make the substitution below raise
        # Encoding::CompatibilityError.
        json = JSON.generate(JSON.parse(File.read(json_path, encoding: Encoding::UTF_8)))
        atomic_write(File.join(output_dir, "index.html"), render_report(json))
      end

    private

      def entry_point_filename
        "index.html"
      end

      def write_report_files(json_hash, viewer_hash)
        atomic_write(File.join(output_path, JSONFormatter::FILENAME), JSON.pretty_generate(json_hash))
        atomic_write(File.join(output_path, "index.html"), render_report(JSON.generate(viewer_hash)))
        FileUtils.rm_f(LEGACY_REPORT_FILES.map { |name| File.join(output_path, name) })
      end

      # Substitute the coverage JSON into the compiled template. `<` is
      # escaped as \u003c — valid JSON, since `<` can only occur inside
      # strings — so embedded source text containing "</script>" or
      # "<!--" cannot terminate the surrounding <script> element. Block
      # forms keep gsub/sub from interpreting backslashes in the JSON as
      # replacement-string back-references.
      def render_report(json)
        # UTF-8 explicitly, not the locale's `Encoding.default_external`:
        # the JSON payload is UTF-8, and substituting it into a template
        # tagged US-ASCII (or a Windows code page) raises
        # Encoding::CompatibilityError the moment either side carries a
        # non-ASCII character.
        template = File.read(File.join(public_dir, "index.html"), encoding: Encoding::UTF_8)
        unless template.include?(DATA_MARKER)
          raise "SimpleCov's HTML template is missing its #{DATA_MARKER.inspect} marker"
        end

        data_script = "<script>window.SIMPLECOV_DATA = #{json.gsub('<') { '\u003c' }};</script>"
        template.sub(DATA_MARKER) { data_script }
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
