# frozen_string_literal: true

module SimpleCov
  class TestTracker
    # The peek-diff arithmetic behind the tracker: which in-root lines grew
    # between two coverage snapshots. This is the part a native
    # `Coverage.supported?(:contexts)` engine would replace outright.
    class Delta
      ONE_BIT = "1".ord

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
      def line_delta(before_lines, after_lines)
        return 0 unless after_lines
        return 0 if same_lines?(before_lines, after_lines)

        grown_bitmap(before_lines || [], after_lines)
      end

      # mutant:disable -- coverage counts are Integers or nil, which answer ==
      # and eql? alike. `==` is kept because it is the faster of the two.
      def same_lines?(before_lines, after_lines)
        before_lines == after_lines
      end

      # mutant:disable -- every index the loop reads from `after_lines` is in
      # bounds, and `before_lines` past its end reads nil through `[]` and
      # `at` alike, so `at` and `fetch` read the same counts. `[]` is kept
      # because it compiles to a specialized instruction.
      #
      # Tuned, since it runs per line of every file a test touched. The bitmap
      # is a binary string preallocated as zeros and filled from its far end,
      # because the number reads highest line first, so the arbitrary-precision
      # math happens once per file, with no per-line append, method call, or
      # final reverse. A `before_lines` shorter than `after_lines`, empty for a
      # file the test itself loaded, reads nil past its end, as never executed.
      def grown_bitmap(before_lines, after_lines)
        size = after_lines.size
        bits = "0" * size
        index = 0
        while index < size
          count = after_lines[index]
          bits.setbyte(size - 1 - index, ONE_BIT) if count && count > (before_lines[index] || 0)
          index += 1
        end
        bits.to_i(2)
      end
    end
  end
end
