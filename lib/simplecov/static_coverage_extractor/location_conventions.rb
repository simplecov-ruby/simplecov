# frozen_string_literal: true

module SimpleCov
  module StaticCoverageExtractor
    # The source ranges Ruby's Coverage assigns to branch conditions and arms,
    # resolved from Prism nodes. Simulated entries only ever merge with real
    # entries produced by the running Ruby, so every resolver here emits the
    # shape this Ruby's Coverage uses (#1226, #1233). The "runtime tuple
    # equivalence" spec exercises the module against real Coverage output on
    # every CI Ruby, and is the authority on what each resolver should answer.
    #
    module LocationConventions
      # A zero-width stand-in for Prism locations, for the arms Coverage
      # anchors to a point rather than a range. Resolvers answer whichever of a
      # node, one of its locations, or this is nearest to hand: all three
      # answer the four position accessors the emitted tuples are built from.
      PointLocation = Data.define(:start_line, :start_column, :end_line, :end_column)

      private

      # The else/elsif clause of an if-like node: an ElseNode, or a nested
      # IfNode for `elsif`. IfNode exposes it as `subsequent`, UnlessNode as
      # `else_clause`.
      def else_clause_of(node, type)
        type.equal?(:if) ? node.subsequent : node.else_clause
      end

      # An empty then body collapses to a zero-width point at the predicate's
      # end for an `if`, and falls back to the node's own range for an
      # `unless`.
      def if_like_then_location(node, type)
        return node.statements if node.statements
        return point_at_end(node.predicate) if type.equal?(:if)

        node
      end

      # With no else/elsif present, the synthesized else inherits the
      # condition's range.
      def if_like_else_location(node, type)
        sub = else_clause_of(node, type)
        return node unless sub
        # An `elsif` arrives as a nested IfNode, and Coverage attributes the
        # outer else arm to the clause's own range, not its then body (which is
        # what created phantom unmergeable arms).
        return sub if sub.instance_of?(Prism::IfNode)
        return sub.statements if sub.statements

        # Empty explicit `else`: an `if` uses the else..end span, an `unless`
        # the condition's range.
        type.equal?(:if) ? sub : node
      end

      def case_arm_location(when_node)
        when_node.statements || when_node
      end

      def else_arm_location(node)
        else_clause = node.else_clause
        return node unless else_clause

        else_clause.statements || else_clause
      end

      def loop_body_location(node)
        node.statements || node
      end

      # Coverage's safe-navigation branch spans the receiver through the end of
      # the call's arguments (or just the message when there are none), but
      # never includes a trailing block: `x&.foo { ... }` ends exactly where
      # `x&.foo` would. `node.location` would include the block (#1233).
      def safe_navigation_location(node)
        span(node, node.closing_loc || node.arguments || node.message_loc)
      end

      def span(from, to)
        PointLocation.new(
          start_line: from.start_line, start_column: from.start_column,
          end_line: to.end_line, end_column: to.end_column
        )
      end

      def point_at_end(location)
        PointLocation.new(
          start_line: location.end_line, start_column: location.end_column,
          end_line: location.end_line, end_column: location.end_column
        )
      end
    end
  end
end
