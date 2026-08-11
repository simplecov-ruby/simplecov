# frozen_string_literal: true

module SimpleCov
  module StaticCoverageExtractor
    # The source ranges Ruby's Coverage assigns to branch conditions and
    # arms, resolved from Prism nodes. Simulated entries only ever merge
    # with real entries produced by the running Ruby, so every resolver
    # here emits the shape this Ruby's Coverage uses — see issues #1226 /
    # #1233, and the "runtime tuple equivalence" spec, which exercises
    # this module against real Coverage output on every CI Ruby.
    module LocationConventions
      # A zero-width stand-in for Prism locations, for the arms Coverage
      # anchors to a point rather than a range.
      PointLocation = Data.define(:start_line, :start_column, :end_line, :end_column)

    private

      # The else/elsif clause of an if-like node: an ElseNode, or a
      # nested IfNode for `elsif`. IfNode exposes it as `subsequent`,
      # UnlessNode as `else_clause`.
      def else_clause_of(node, type)
        type == :if ? node.subsequent : node.else_clause
      end

      # Location of the then arm. Coverage uses the body statements'
      # range; with an empty then body the arm collapses to a zero-width
      # point at the predicate's end for an `if`, and falls back to the
      # node's range for an `unless`.
      def if_like_then_location(node, type)
        return node.statements.location if node.statements
        return point_at_end(node.predicate.location) if type == :if

        node.location
      end

      # Resolve the source range Coverage attributes to a real-or-synthetic
      # `:else` arm of an if-like construct. When no else/elsif is present,
      # the synthesized else inherits the condition's range (matches
      # Coverage's convention).
      def if_like_else_location(node, type)
        sub = else_clause_of(node, type)
        return node.location unless sub
        # An `elsif` arrives as a nested IfNode. Coverage attributes the
        # outer else arm to the clause's own range, not its then body
        # (which is what created phantom unmergeable arms).
        return sub.location if sub.is_a?(::Prism::IfNode)
        return sub.statements.location if sub.statements

        # Empty explicit `else`: an `if` uses the else..end span, an
        # `unless` the condition's range.
        type == :if ? sub.location : node.location
      end

      # Arm location for a when/in clause: its body statements, or the
      # clause's own range when the body is empty.
      def case_arm_location(when_node)
        when_node.statements ? when_node.statements.location : when_node.location
      end

      # Resolve the source range Coverage attributes to a synthetic-or-real
      # `:else` arm of a case construct: the body of an explicit else,
      # the case's full range when no else is present, and — for an
      # explicit else with an empty body — the else..end span.
      def else_arm_location(node)
        else_clause = node.else_clause
        return node.location unless else_clause

        else_clause.statements ? else_clause.statements.location : else_clause.location
      end

      # An empty loop body falls back to the loop's range.
      def loop_body_location(node)
        node.statements ? node.statements.location : node.location
      end

      # Coverage's safe-navigation branch spans the receiver through the
      # end of the call's arguments (or just the message when there are
      # none), but never includes a trailing block: `x&.foo { ... }` and
      # `x&.foo(1) { ... }` both end exactly where `x&.foo` / `x&.foo(1)`
      # would without the block. `node.location` includes an attached
      # block, so build the end position from `closing_loc` (closing
      # paren) / `arguments` (paren-less args) / `message_loc` instead.
      # See issue #1233.
      def safe_navigation_location(node)
        span(node.location, node.closing_loc || node.arguments&.location || node.message_loc)
      end

      # The range from `from`'s start through `to`'s end.
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
