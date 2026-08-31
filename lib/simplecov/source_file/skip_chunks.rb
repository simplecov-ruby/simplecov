# frozen_string_literal: true

module SimpleCov
  class SourceFile
    # The line ranges excluded from a SourceFile's coverage per criterion. Two
    # sources contribute: the deprecated nocov block toggle, and the
    # `SimpleCov::Directive` block directives, which can be scoped per criterion.
    class SkipChunks
      @nocov_warned = Set.new
      class << self
        attr_reader :nocov_warned
      end

      def initialize(filename, src)
        @filename = filename
        @src = src
      end

      # Every criterion honors the deprecated all-criteria nocov chunks plus its
      # own per-criterion directive ranges, methods included: they carry a
      # source range, and nocov has always meant "exclude everything here". The
      # ranges are 1-based line numbers, so consumers subtract 1 to index into
      # the zero-based lines array.
      def for(criterion)
        nocov_chunks + directive_chunks.fetch(criterion)
      end

      def nocov_chunks
        @nocov_chunks ||= build_nocov_chunks
      end

      def directive_chunks
        @directive_chunks ||= Directive.disabled_ranges(@src)
      end

    private

      # An uneven number of nocovs is assumed to run to the end of the file. It
      # cannot be handled inside the each_slice because JRuby behaves differently
      # there (jruby/jruby#6048).
      def build_nocov_chunks
        no_cov_lines = @src.filter_map.with_index(1) do |line_src, index|
          index if LinesClassifier.no_cov_line?(line_src)
        end

        warn_nocov_deprecation(no_cov_lines.first) if no_cov_lines.any?

        no_cov_lines << @src.size if no_cov_lines.size.odd?

        no_cov_lines.each_slice(2).map { |chunk_start, chunk_end| chunk_start..chunk_end }
      end

      # at the `# simplecov:disable` / `# simplecov:enable` replacement.
      def warn_nocov_deprecation(first_line_number)
        return unless self.class.nocov_warned.add?(@filename)

        token = SimpleCov.current_nocov_token
        warn "#{@filename}:#{first_line_number}: [DEPRECATION] `# :#{token}:` is deprecated and will be removed " \
             "in a future release. Replace with `# simplecov:disable` / `# simplecov:enable` block comments."
      end
    end
  end
end
