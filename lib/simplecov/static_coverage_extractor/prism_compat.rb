# frozen_string_literal: true

module SimpleCov
  module StaticCoverageExtractor
    # The Prism 1.3 accessor renames for the trailing clause of conditional
    # nodes, resolved once at load so the per-node hot paths stay branch-free.
    # Ruby 3.3's stdlib Prism predates the renames; 3.4+ and any installed prism
    # gem post-date them, and reaching for the modern name on the old one raised
    # NoMethodError inside the extractor, which `call` swallowed, silently
    # falling back to no simulated data.
    #
    # This lives in its own file, required by every consumer, because the
    # constants are referenced from several extractor files and defining them
    # after those files were loaded worked only while the references happened at
    # call time: a load-order trap for the next editor.
    module PrismCompat
      extend self

      # simplecov:disable
      IF_NODE_SUBSEQUENT_METHOD =
        if Prism::IfNode.method_defined?(:subsequent)
          :subsequent
        else
          :consequent
        end

      ELSE_CLAUSE_METHOD =
        if Prism::CaseNode.method_defined?(:else_clause)
          :else_clause
        else
          :consequent
        end
      # simplecov:enable

      def subsequent(node)
        node.instance_of?(Prism::IfNode) ? node.public_send(IF_NODE_SUBSEQUENT_METHOD) : else_clause(node)
      end

      # The rename hit `UnlessNode`, `CaseNode`, and `CaseMatchNode` together, so
      # one constant probed off CaseNode covers all three.
      def else_clause(node)
        node.public_send(ELSE_CLAUSE_METHOD)
      end
    end
  end
end
