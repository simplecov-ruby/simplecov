# frozen_string_literal: true

module SimpleCov
  class SourceFile
    # Builds the `SourceFile::Line` objects for a source file from the
    # raw line-coverage array. Each line carries its source text, its
    # 1-based line number, and the Coverage hit count (or nil for
    # never-counted lines). Applies `# simplecov:disable` /
    # `# :nocov:` block ranges via `skipped!`.
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

      # When `:line` coverage is disabled, the Ruby Coverage module
      # doesn't emit "lines" data, so look up `nil` (never-counted) for
      # every position. The source rows are still useful — e.g. for the
      # HTML report's source view — even without per-line hits.
      def build_lines
        line_coverage = @source_file.coverage_data["lines"] || []
        @source_file.src.map.with_index(1) do |src, i|
          SourceFile::Line.new(src, i, line_coverage[i - 1])
        end
      end

      # The array the lines are kept in is 0-based whereas the line
      # numbers in the chunks are 1-based (more understandable elsewhere),
      # so each range needs to be shifted down by one to slice into the
      # `lines` array.
      def mark_skipped(lines, chunks)
        chunks.each { |chunk| lines[(chunk.begin - 1)..(chunk.end - 1)].each(&:skipped!) }
      end
    end
  end
end
