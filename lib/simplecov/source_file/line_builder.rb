# frozen_string_literal: true

module SimpleCov
  class SourceFile
    # Builds the `SourceFile::Line` objects for a source file from the raw
    # line-coverage array, applying the disabled block ranges via `skipped!`.
    class LineBuilder
      def initialize(source_file)
        @source_file = source_file
      end

      def call
        lines = build_lines
        mark_skipped(lines, @source_file.skip_chunks_for(:line))
        lines
      end

      private

      # When `:line` coverage is disabled the Coverage module emits no "lines" data,
      # so every position looks up nil. The source rows are still useful for the
      # HTML report's source view even without per-line hits.
      def build_lines
        line_coverage = @source_file.coverage_data["lines"] || []
        @source_file.src.map.with_index(1) do |src, i|
          Line.new(src, i, line_coverage.at(i - 1))
        end
      end

      # The lines array is 0-based while the chunks' line numbers are 1-based, so
      # each range is shifted down by one to slice into it.
      def mark_skipped(lines, chunks)
        chunks.each { |chunk| lines[(chunk.begin - 1)..(chunk.end - 1)].each(&:skipped!) }
      end
    end
  end
end
