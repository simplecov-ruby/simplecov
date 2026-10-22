# frozen_string_literal: true

module SimpleCov
  class TestTracker
    # The lines of a Ruby file that sit inside method bodies, as bitmaps in the
    # `ContextMap` encoding. A test that first loads a file runs its class
    # bodies and `def` lines on behalf of every later test, so only what ran
    # inside a method body is the test's own.
    #
    # A one-line method's body shares its `def` line, so its line is masked
    # apart: it ran once as the file loaded, and any count beyond that is the
    # method running. Not every body counts the line again (Ruby skips the
    # line event of a body that starts with a plain call), and a line no test
    # can claim falls back to the full suite. When the file cannot be read as
    # Ruby (a template, a path that only names an eval, a Ruby without Prism)
    # every line counts, as it did before this distinction existed.
    module MethodBodies
      EVERY_LINE = -1

      extend self

      # The body lines, and the lines of one-line methods.
      def masks(path)
        return [EVERY_LINE, 0] unless path.end_with?(".rb") && StaticCoverageExtractor.prism_loaded?

        collect(Prism.parse_file(path).value, [0, 0])
      rescue SystemCallError
        [EVERY_LINE, 0]
      end

      private

      def collect(node, masks)
        masks = add_method(node, masks) if node.instance_of?(Prism::DefNode)
        node.compact_child_nodes.reduce(masks) { |combined, child| collect(child, combined) }
      end

      def add_method(node, masks)
        bodies, one_liners = masks
        body = node.body
        line = node.start_line
        one_liners |= 1 << (line - 1) if body&.start_line.eql?(line)
        [bodies | span(line + 1, body&.end_line), one_liners]
      end

      # A body on the `def` line ends one line before `first`, an empty span.
      def span(first, last)
        return 0 unless last

        ((1 << (last - first + 1)) - 1) << (first - 1)
      end
    end
  end
end
