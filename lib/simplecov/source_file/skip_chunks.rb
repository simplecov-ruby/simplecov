# frozen_string_literal: true

module SimpleCov
  class SourceFile
    # Computes the set of line ranges that should be excluded from a
    # SourceFile's coverage for each criterion. Two sources contribute:
    #
    # * The deprecated `# :nocov:` block toggle (lines wrapped between
    #   even-numbered pairs of nocov markers are excluded from line and
    #   branch coverage).
    # * `# simplecov:disable` / `# simplecov:enable` block directives,
    #   which can be scoped per-criterion (`# simplecov:disable branch`,
    #   etc.) — see `SimpleCov::Directive`.
    class SkipChunks
      @nocov_warned = Set.new
      class << self
        attr_reader :nocov_warned
      end

      def initialize(filename, src)
        @filename = filename
        @src = src
      end

      # Every criterion honors the deprecated all-criteria `# :nocov:`
      # chunks plus its own per-criterion directive ranges. Methods
      # included: they carry a source range, and nocov has always meant
      # "exclude everything here".
      def for(criterion)
        nocov_chunks + directive_chunks.fetch(criterion)
      end

      # Ranges of 1-based line numbers (see `with_index(1)` below);
      # consumers subtract 1 to index into the zero-based lines array.
      def nocov_chunks
        @nocov_chunks ||= build_nocov_chunks
      end

      def directive_chunks
        @directive_chunks ||= Directive.disabled_ranges(@src)
      end

    private

      def build_nocov_chunks
        no_cov_lines = @src.map.with_index(1).select { |line_src, _index| LinesClassifier.no_cov_line?(line_src) }

        warn_nocov_deprecation(no_cov_lines.first.last) if no_cov_lines.any?

        # If we have an uneven number of nocovs we assume they go to the
        # end of the file, the source doesn't really matter.
        no_cov_lines << ["", @src.size] if no_cov_lines.size.odd?

        no_cov_lines.each_slice(2).map do |(_line_src_start, index_start), (_line_src_end, index_end)|
          index_start..index_end
        end
      end

      # Emit a one-time-per-file deprecation warning pointing the user
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
