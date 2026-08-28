# frozen_string_literal: true

module SimpleCov
  class TestTracker
    # The peek-diff arithmetic behind the tracker: which in-root lines
    # grew between two coverage snapshots. Split from the tracker so the
    # segment bookkeeping and the engine stay separately readable — this
    # class is the part a native `Coverage.supported?(:contexts)` engine
    # would replace outright.
    class Delta
      def initialize(root_regex:)
        @root_regex = root_regex
        @in_root = {} #: Hash[String, bool]
      end

      # The per-file bitmaps of lines whose count grew between the two peeks.
      # Files outside the root are skipped (see `initialize`); a file absent
      # from `before` was loaded by the test itself, so everything it
      # executed is the test's.
      def call(before, after)
        changed = {} #: Hash[String, Integer]
        after.each do |path, file_coverage|
          # Memoized: the regex runs once per file the process ever loads,
          # not once per file per test.
          in_root = @in_root.fetch(path) { @in_root[path] = @root_regex.match?(path) }
          next unless in_root

          bitmap = line_delta(lines_in(before[path]), lines_in(file_coverage))
          changed[path] = bitmap unless bitmap.zero?
        end
        changed
      end

    private

      # A peek's per-file data is a criteria Hash when Coverage was started
      # with a criteria hash (how SimpleCov starts it) and a bare Array under
      # the older lines-only form (how someone else may have started it). No
      # lines at all — a branch-only or method-only start — means nothing to
      # diff.
      def lines_in(file_coverage)
        case file_coverage
        when Hash then file_coverage[:lines]
        when Array then file_coverage
        end
      end

      def line_delta(before_lines, after_lines)
        return 0 unless after_lines
        # The overwhelmingly common case: the test never entered this file.
        # Array equality is a fast C compare, the per-line loop is not.
        return 0 if before_lines.eql?(after_lines)

        # Built as a binary string, one pass over the lines, so the
        # arbitrary-precision math happens once per file rather than one
        # bignum OR per executed line. The string reads lowest line
        # first and the number wants it the other way round; the leading
        # zero keeps the parse valid for an all-zero delta without
        # changing any value.
        bits = +""
        after_lines.each_with_index do |count, index|
          bits << (grew?(count, before_lines&.at(index)) ? "1" : "0")
        end
        Integer("0#{bits.reverse}", 2)
      end

      # A line belongs to the test when its count grew across the two peeks.
      # `previous` is nil both for a non-executable line (whose count is nil
      # too) and for a file the test itself loaded, where every executed
      # line is the test's.
      def grew?(count, previous)
        !count.nil? && count > (previous || 0)
      end
    end
  end
end
