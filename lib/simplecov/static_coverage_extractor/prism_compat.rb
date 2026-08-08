# frozen_string_literal: true

module SimpleCov
  module StaticCoverageExtractor
    # The Prism 1.3 (Dec 2024) accessor renames for the trailing clause of
    # conditional nodes, resolved ONCE at load so the per-node hot paths
    # stay branch-free. Ruby 3.3's stdlib Prism (0.19) predates the
    # renames; 3.4+ and any installed prism gem post-dates them. Reaching
    # for the modern name on 0.19 raised NoMethodError inside the
    # extractor — `call` swallowed it and the whole file silently fell
    # back to no simulated data (see the 1.0.2 audit).
    #
    # This lives in its own file, required by every consumer, because the
    # constants are referenced from several extractor files and defining
    # them after those files were loaded worked only while the references
    # happened at call time — a load-order trap for the next editor.
    module PrismCompat
    module_function

      # `Prism::IfNode#subsequent` was renamed from `consequent`. The
      # not-taken arm on whichever Prism version we're on can't be
      # exercised by our own dogfood (we only run on one Prism at a time).
      # simplecov:disable
      IF_NODE_SUBSEQUENT_METHOD =
        if ::Prism::IfNode.method_defined?(:subsequent)
          :subsequent
        else
          :consequent
        end

      # The same rename hit the `else` accessor on `UnlessNode`,
      # `CaseNode`, and `CaseMatchNode` (all three: `consequent` ->
      # `else_clause`). All three renamed together, so one constant
      # (probed off CaseNode) covers them.
      ELSE_CLAUSE_METHOD =
        if ::Prism::CaseNode.method_defined?(:else_clause)
          :else_clause
        else
          :consequent
        end
      # simplecov:enable

      # The `else`/`elsif` clause of an if-like node (an ElseNode, or a
      # nested IfNode for `elsif`), or the `else` clause of anything else
      # that has one, under whichever accessor this Prism exposes.
      def subsequent(node)
        node.is_a?(::Prism::IfNode) ? node.public_send(IF_NODE_SUBSEQUENT_METHOD) : else_clause(node)
      end

      def else_clause(node)
        node.public_send(ELSE_CLAUSE_METHOD)
      end
    end
  end
end
