# frozen_string_literal: true

module SimpleCov
  class SourceFile
    module BuilderContext
      def skip_chunks_for(criterion)
        (@skip_chunks ||= SkipChunks.new(filename, src)).chunks_for(criterion)
      end

      # Memoized set of real source positions extracted via Prism. Nil when Prism is
      # unavailable or parsing fails, signaling callers to keep every Coverage entry
      # rather than risk false drops. The `defined?` guard preserves a nil
      # memoization across calls.
      def real_source_positions
        return @real_source_positions if instance_variable_defined?(:@real_source_positions)

        @real_source_positions = StaticCoverageExtractor.real_source_positions(src.join)
      end
    end
  end
end
