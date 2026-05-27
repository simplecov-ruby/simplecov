# frozen_string_literal: true

module SimpleCov
  class SourceFile
    # Helpers shared by the per-criterion builders (LineBuilder /
    # BranchBuilder / MethodBuilder). Mixed into SourceFile so each
    # builder can ask the file for its skip-chunk ranges and Prism-derived
    # real source positions without duplicating the memoization.
    module BuilderContext
      # Skip-chunk lookup for the named criterion (`:line`, `:branch`,
      # `:method`).
      def skip_chunks_for(criterion)
        (@skip_chunks ||= SkipChunks.new(filename, src)).for(criterion)
      end

      # Memoized set of real source positions (branch start lines, method
      # name+line pairs) extracted via Prism. Returns nil when Prism is
      # unavailable or parsing fails, signaling callers to keep every
      # Coverage entry (no false drops). The `defined?` guard preserves a
      # nil memoization across calls.
      def real_source_positions
        return @real_source_positions if defined?(@real_source_positions)

        @real_source_positions = StaticCoverageExtractor.real_source_positions(src.join)
      end
    end
  end
end
