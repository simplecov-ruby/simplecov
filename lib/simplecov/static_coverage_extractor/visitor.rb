# frozen_string_literal: true

require_relative "condition_folding"
require_relative "location_conventions"
require_relative "method_collector"

module SimpleCov
  module StaticCoverageExtractor
    # Prism visitor that accumulates branch and method tuples in the shape
    # Ruby's `Coverage` reports. Tuple ids are sequential across the file like
    # `Coverage`'s, but the numbering order can differ. That's fine: the
    # combiners intern on source span and the report output drops ids, so
    # nothing downstream compares them.
    class Visitor < Prism::Visitor
      include MethodCollector
      include LocationConventions
      include ConditionFolding

      attr_reader :branches, :methods

      # Prism's Visitor is a stateless dispatch table whose initializer is
      # Object's, so no mutation of the `super` call can be told apart. It
      # stays for the day that stops being true.
      # mutant:disable
      def initialize
        super
        @branches = {}
        @methods = {}
        @next_id = 0
        @class_stack = []
      end

      # `if` / `unless` / postfix / ternary all parse as IfNode (or UnlessNode).
      # Both carry a `then` arm and an optional `subsequent` (an ElseNode for
      # `else`, another IfNode for `elsif`). When the subsequent is missing,
      # Coverage synthesizes a `:else` arm attributed to the whole condition's
      # range, and so do we.
      #
      # A folded condition emits no tuple, and only its live arm is descended
      # into: the compiler eliminates the dead arm's entire subtree, so a branch
      # or method nested there would be a phantom no loaded run can produce.
      def visit_if_node(node)
        verdict = folded_condition(node.predicate)
        return visit_folded_arms(verdict, node.statements, node.subsequent) if verdict

        emit_if_like(node, :if)
        super
      end

      def visit_unless_node(node)
        verdict = folded_condition(node.predicate)
        return visit_folded_arms(verdict, node.else_clause, node.statements) if verdict

        emit_if_like(node, :unless)
        super
      end

      def visit_call_node(node)
        emit_safe_navigation(node) if node.safe_navigation?
        super
      end

      # When there's no explicit `else`, Coverage synthesizes one at the case's
      # range.
      def visit_case_node(node)
        emit_case_like(node, :when)
        super
      end

      def visit_case_match_node(node)
        emit_case_like(node, :in)
        super
      end

      # A loop gets a single `:body` arm and no synthetic else.
      def visit_while_node(node)
        emit_loop(node, :while)
        super
      end

      def visit_until_node(node)
        emit_loop(node, :until)
        super
      end

      private

      # IfNode and UnlessNode share a shape but expose the trailing arm under
      # different accessors, which `if_like_else_location` hides.
      def emit_if_like(node, type)
        then_loc = if_like_then_location(node, type)
        else_loc = if_like_else_location(node, type)
        @branches[build_tuple(type, node)] = {
          build_tuple(:then, then_loc) => 0,
          build_tuple(:else, else_loc) => 0
        }
      end

      def emit_safe_navigation(node)
        loc = safe_navigation_location(node)
        @branches[build_tuple(:"&.", loc)] = {
          build_tuple(:then, loc) => 0,
          build_tuple(:else, loc) => 0
        }
      end

      def emit_case_like(node, when_type)
        arms = node.conditions.to_h do |when_node|
          [build_tuple(when_type, case_arm_location(when_node)), 0]
        end
        arms[build_tuple(:else, else_arm_location(node))] = 0
        @branches[build_tuple(:case, node)] = arms
      end

      def emit_loop(node, type)
        cond_tuple = build_tuple(type, node)
        @branches[cond_tuple] = {build_tuple(:body, loop_body_location(node)) => 0}
      end

      # `span` is anything that answers the four position accessors: a location
      # from LocationConventions, or the node itself where the range wanted is
      # the node's own.
      def build_tuple(type, span)
        id = @next_id
        @next_id += 1
        [type, id, span.start_line, span.start_column, span.end_line, span.end_column]
      end
    end
  end
end
