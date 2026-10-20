# frozen_string_literal: true

module SimpleCov
  class TestTracker
    # The lines of a Ruby file that sit inside method bodies, as a bitmap in the
    # `ContextMap` encoding. A test that first loads a file runs its class
    # bodies and `def` lines on behalf of every later test, so only what ran
    # inside a method body is the test's own.
    #
    # A `def` line is never a body line, which leaves a one-line method to no
    # test. When the file cannot be read as Ruby (a template, a path that only
    # names an eval, a Ruby without Prism) every line counts, as it did before
    # this distinction existed.
    module MethodBodies
      EVERY_LINE = -1

      extend self

      def mask(path)
        return EVERY_LINE unless path.end_with?(".rb") && StaticCoverageExtractor.prism_loaded?

        body_lines(Prism.parse_file(path).value, 0)
      rescue SystemCallError
        EVERY_LINE
      end

      private

      def body_lines(node, mask)
        mask |= span(node.start_line + 1, node.body&.end_line) if node.instance_of?(Prism::DefNode)
        node.compact_child_nodes.reduce(mask) { |combined, child| body_lines(child, combined) }
      end

      # A body on the `def` line ends one line before `first`, an empty span.
      def span(first, last)
        return 0 unless last

        ((1 << (last - first + 1)) - 1) << (first - 1)
      end
    end
  end
end
