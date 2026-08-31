# frozen_string_literal: true

module SimpleCov
  class TestTracker
    # The peek-diff arithmetic behind the tracker: which in-root lines grew
    # between two coverage snapshots. This is the part a native
    # `Coverage.supported?(:contexts)` engine would replace outright.
    class Delta
      def initialize(root_regex:)
        @root_regex = root_regex
        @in_root = {} #: Hash[String, bool]
      end

      # Files outside the root are skipped; a file absent from `before` was loaded
      # by the test itself, so everything it executed is the test's. The root match
      # is memoized, so the regex runs once per file the process ever loads rather
      # than once per file per test.
      def call(before, after)
        changed = {} #: Hash[String, Integer]
        after.each do |path, file_coverage|
          in_root = @in_root.fetch(path) { @in_root[path] = @root_regex.match?(path) }
          next unless in_root

          bitmap = line_delta(lines_in(before[path]), lines_in(file_coverage))
          changed[path] = bitmap unless bitmap.zero?
        end
        changed
      end

    private

      # A peek's per-file data is a criteria Hash when Coverage was started with a
      # criteria hash, and a bare Array under the older lines-only form. No lines
      # at all, from a branch-only or method-only start, means nothing to diff.
      def lines_in(file_coverage)
        case file_coverage
        when Hash then file_coverage[:lines]
        when Array then file_coverage
        end
      end

      # The equality check is the overwhelmingly common case, the test never
      # entering this file: an Array compare is fast C, the per-line loop is not.
      #
      # The bitmap is built as a binary string in one pass, so the
      # arbitrary-precision math happens once per file rather than one bignum OR
      # per executed line. The string reads lowest line first and the number wants
      # it the other way round; the leading zero keeps the parse valid for an
      # all-zero delta without changing any value.
      def line_delta(before_lines, after_lines)
        return 0 unless after_lines
        return 0 if before_lines.eql?(after_lines)

        bits = +""
        after_lines.each_with_index do |count, index|
          bits << (grew?(count, before_lines&.at(index)) ? "1" : "0")
        end
        Integer("0#{bits.reverse}", 2)
      end

      # `previous` is nil both for a non-executable line, whose count is nil too,
      # and for a file the test itself loaded, where every executed line is the
      # test's.
      def grew?(count, previous)
        !count.nil? && count > (previous || 0)
      end
    end
  end
end
