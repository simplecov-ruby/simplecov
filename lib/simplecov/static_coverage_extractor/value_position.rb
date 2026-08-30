# frozen_string_literal: true

require_relative "prism_compat"

module SimpleCov
  module StaticCoverageExtractor
    # Ruby 3.3 value-position analysis for the extractor's legacy branch
    # conventions (see LocationConventions and the #1233 audit).
    #
    # On Ruby 3.3, the source range Coverage assigns to an EMPTY branch arm
    # depends on whether its construct is in value position — its result is
    # the method's return value — or void position, where the result is
    # discarded. Value position keeps the whole-construct range; void
    # collapses the arm to a point at its header's end. Ruby 3.4 dropped the
    # distinction, so this pass only runs on legacy Rubies.
    #
    # "Value position" here is narrower than general value-use: it is
    # strictly method-return (tail) position. It reaches a node only through
    # statement tails and `if`/`unless`/`when` arms. Assignments, blocks,
    # lambdas, method arguments, `case/in` arms, and loop bodies all discard
    # it (Coverage treats their empty arms as void). So `tail_children`
    # names the constructs that forward tail position and everything else
    # falls through to the void default.
    module ValuePositions
      extend self

      # This pass runs natively only on legacy Rubies; elsewhere the
      # specs drive it directly, and its behavior is pinned by the
      # differential tuple-equivalence spec against real Coverage on 3.3.

      # An identity set (a `compare_by_identity` Hash used as a set) of the
      # Prism nodes Coverage treats as being in value position.
      def call(root)
        positions = {} #: Hash[untyped, bool]
        positions.compare_by_identity
        mark(root, true, positions)
        positions
      end

      def mark(node, in_value, positions)
        return unless node.is_a?(Prism::Node)

        positions[node] = true if in_value
        children = tail_children(node, in_value)
        node.compact_child_nodes.each do |child|
          mark(child, children.any? { |c| c.equal?(child) }, positions)
        end
      end

      # The children of `node` that inherit its tail position; empty for the
      # void default. A method body is a tail context even when the `def`
      # itself is not (the method still returns its last expression), so it
      # is included regardless of `in_value`.
      def tail_children(node, in_value)
        # A method body is a tail context even when the `def` is not.
        return [node.body] if node.instance_of?(Prism::DefNode)
        return [] unless in_value

        # `case/in` (CaseMatchNode) is intentionally not a tail construct:
        # its `in` arms and `else` both discard tail position.
        case node
        when Prism::StatementsNode then [node.body.last]
        when Prism::IfNode, Prism::UnlessNode then [node.statements, PrismCompat.subsequent(node)]
        when Prism::CaseNode then [*node.conditions, PrismCompat.else_clause(node)]
        when Prism::ElseNode, Prism::WhenNode, Prism::BeginNode, Prism::ProgramNode then [node.statements]
        else []
        end
      end
    end
  end
end
