# frozen_string_literal: true

require_relative "method_collector"

module SimpleCov
  module StaticCoverageExtractor
    # `Prism::IfNode#subsequent` was renamed from `consequent` in Prism
    # 1.3 (Dec 2024). Ruby 3.3's stdlib still ships an older Prism that
    # only exposes `consequent`; 3.4+ and any project that's done
    # `gem install prism` exposes `subsequent`. Resolve the method name
    # ONCE here so the per-node hot path stays branch-free. The
    # not-taken arm on whichever Prism version we're on can't be
    # exercised by our own dogfood (we only run on one Prism at a time).
    # simplecov:disable
    IF_NODE_SUBSEQUENT_METHOD =
      if ::Prism::IfNode.method_defined?(:subsequent)
        :subsequent
      else
        :consequent
      end
    # simplecov:enable

    # Prism visitor that accumulates branch and method tuples in the
    # shape Ruby's `Coverage` reports. Tuple ids are sequential across
    # the file — `Coverage` uses sequential ids too, so this matches the
    # conventional shape. Only defined when Prism is loadable;
    # `StaticCoverageExtractor.available?` is the runtime gate.
    class Visitor < ::Prism::Visitor
      # Method tuples and the class/module nesting that names them are
      # collected by this mixin; this class focuses on branch extraction.
      include MethodCollector

      attr_reader :branches, :methods

      # A zero-width stand-in for Prism locations, for the arms Coverage
      # anchors to a point rather than a range (an `if` with an empty
      # then body gets a collapsed range at the predicate's end).
      PointLocation = Data.define(:start_line, :start_column, :end_line, :end_column)

      def initialize
        super
        @branches = {}
        @methods = {}
        @next_id = 0
        @class_stack = []
      end

      # `if` / `unless` / postfix-if / postfix-unless / ternary all parse
      # as IfNode (or UnlessNode). Both carry a `then` arm (the
      # statements body) and an optional `subsequent` (an ElseNode for
      # `else`, another IfNode for `elsif`). When the subsequent is
      # missing, Coverage synthesizes a `:else` arm attributed to the
      # whole condition's range — we do the same.
      def visit_if_node(node)
        emit_if_like(node, :if)
        super
      end

      def visit_unless_node(node)
        emit_if_like(node, :unless)
        super
      end

      def visit_call_node(node)
        emit_safe_navigation(node) if node.respond_to?(:safe_navigation?) && node.safe_navigation?
        super
      end

      # `case`/`when` and `case`/`in` (pattern matching) parse as CaseNode
      # and CaseMatchNode respectively. When there's no explicit `else`,
      # Coverage synthesizes one at the case's range.
      def visit_case_node(node)
        emit_case_like(node, :when)
        super
      end

      def visit_case_match_node(node)
        emit_case_like(node, :in)
        super
      end

      # `while` / `until` loops get a single `:body` arm. No synthetic
      # else (the loop either runs the body or doesn't).
      def visit_while_node(node)
        emit_loop(node, :while)
        super
      end

      def visit_until_node(node)
        emit_loop(node, :until)
        super
      end

    private

      # IfNode and UnlessNode share a shape (predicate + then body +
      # optional else/elsif) but expose the trailing arm under different
      # accessors. `if_like_else_location` hides that split.
      def emit_if_like(node, type)
        then_loc = if_like_then_location(node, type)
        else_loc = if_like_else_location(node)
        @branches[build_tuple(type, node.location)] = {
          build_tuple(:then, then_loc) => 0,
          build_tuple(:else, else_loc) => 0
        }
      end

      def emit_safe_navigation(node)
        loc = node.location
        @branches[build_tuple(:"&.", loc)] = {
          build_tuple(:then, loc) => 0,
          build_tuple(:else, loc) => 0
        }
      end

      # Location of the then arm. Coverage uses the body statements'
      # range; when an `if` (but not an `unless`) has an empty then body,
      # it collapses the arm to a zero-width point at the predicate's
      # end. See issue #1226.
      def if_like_then_location(node, type)
        return node.statements.location if node.statements
        return node.location unless type == :if

        predicate_end = node.predicate.location
        PointLocation.new(
          start_line: predicate_end.end_line, start_column: predicate_end.end_column,
          end_line: predicate_end.end_line, end_column: predicate_end.end_column
        )
      end

      # Resolve the source range Coverage attributes to a real-or-synthetic
      # `:else` arm of an if-like construct. IfNode uses
      # `subsequent` / `consequent` depending on Prism version (resolved
      # to `IF_NODE_SUBSEQUENT_METHOD` at load time); UnlessNode uses
      # `else_clause`. When neither is present, the synthesized else
      # inherits the whole condition's range (matches Coverage's
      # convention).
      def if_like_else_location(node)
        sub = node.is_a?(::Prism::IfNode) ? node.public_send(IF_NODE_SUBSEQUENT_METHOD) : node.else_clause
        return node.location unless sub
        # An `elsif` arrives as a nested IfNode. Coverage attributes the
        # outer else arm to the whole clause (from the `elsif` keyword
        # through the shared `end`), which is the nested node's own
        # location — not its then body, which is what `else_body_of`
        # would yield and what created phantom unmergeable arms. See
        # issue #1226.
        return sub.location if sub.is_a?(::Prism::IfNode)

        arm_location(else_body_of(sub), sub.location)
      end

      def emit_case_like(node, when_type)
        arms = node.conditions.to_h do |when_node|
          loc = arm_location(when_node.statements, when_node.location)
          [build_tuple(when_type, loc), 0]
        end
        arms[build_tuple(:else, else_arm_location(node))] = 0
        @branches[build_tuple(:case, node.location)] = arms
      end

      # Resolve the source range Coverage attributes to a synthetic-or-real
      # `:else` arm of a case construct: the body of an explicit else,
      # or the case's full range when no else is present.
      def else_arm_location(node)
        return node.location unless node.else_clause

        arm_location(else_body_of(node.else_clause), node.else_clause.location)
      end

      def emit_loop(node, type)
        cond_tuple = build_tuple(type, node.location)
        body_loc = arm_location(node.statements, node.location)
        @branches[cond_tuple] = {build_tuple(:body, body_loc) => 0}
      end

      # Body location for an arm. Prism's `statements` is a StatementsNode
      # whose span covers the contained expressions; fall back to the
      # parent when the arm body is empty (e.g., `if cond then end`).
      def arm_location(statements, fallback_location)
        statements&.location || fallback_location
      end

      # simplecov:disable branch
      # The `else_node` fallback is defensive: every Prism node passed
      # in here in practice responds to `:statements`.
      def else_body_of(else_node)
        else_node.respond_to?(:statements) ? else_node.statements : else_node
      end
      # simplecov:enable branch

      def build_tuple(type, location)
        id = @next_id
        @next_id += 1
        [type, id, location.start_line, location.start_column, location.end_line, location.end_column]
      end
    end
  end
end
