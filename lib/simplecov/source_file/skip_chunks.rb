# frozen_string_literal: true

module SimpleCov
  class SourceFile
    # Computes the set of line ranges that should be excluded from a
    # SourceFile's coverage for each criterion, from the
    # `# simplecov:disable` / `# simplecov:enable` block directives, which
    # can be scoped per-criterion (`# simplecov:disable branch`, etc.) —
    # see `SimpleCov::Directive`.
    class SkipChunks
      def initialize(filename, src)
        @filename = filename
        @src = src
      end

      # Ranges of 1-based line numbers; consumers subtract 1 to index into
      # the zero-based lines array.
      def for(criterion)
        directive_chunks.fetch(criterion)
      end

      def directive_chunks
        @directive_chunks ||= Directive.disabled_ranges(@src)
      end
    end
  end
end
