# frozen_string_literal: true

require_relative "condition_folding"
require_relative "location_conventions"
require_relative "method_collector"

module SimpleCov
  module StaticCoverageExtractor
    # Prism visitor that accumulates branch and method tuples in the
    # shape Ruby's `Coverage` reports. Tuple ids are sequential across
    # the file like `Coverage`'s, but the numbering order can differ
    # (e.g. `case`/`when` and chained `&.` are visited in a different
    # order than Coverage numbers them). That's fine: the combiners
    # intern on source span and the report output drops ids, so nothing
    # downstream compares them.
    class Visitor < ::Prism::Visitor
      # Method tuples and the class/module nesting that names them are
      # collected by this mixin; this class focuses on branch extraction.
      include MethodCollector
      # Source-range resolution matching Coverage's conventions. See
      # issue #1226.
      include LocationConventions
      # Which literal `if`/`unless`/ternary conditions the compiler folds
      # away (so we emit no branch for them).
      include ConditionFolding

      attr_reader :branches, :methods

      def initialize
        super
        @branches = {}
        @methods = {}
        @next_id = 0
        @class_stack = []
      end

      # `if` / `unless` / postfix-if / postfix-unless / ternary all parse
      # as IfNode (or UnlessNode). Both carry a `then` arm (the
      # statements body) and an optional trailing clause (an ElseNode for
      # `else`, another IfNode for `elsif`). When the trailing clause is
      # missing, Coverage synthesizes a `:else` arm attributed to the
      # whole condition's range — we do the same.
      #
      # A folded condition emits no tuple, and only its live arm is
      # descended into: the compiler eliminates the dead arm's entire
      # subtree, so a branch or method nested there would be a phantom no
      # loaded run can produce. A falsy `if`'s elsif chain survives as a
      # plain `if`, which is what visiting the subsequent IfNode emits.
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
        else_loc = if_like_else_location(node, type)
        @branches[build_tuple(type, node.location)] = {
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
        @branches[build_tuple(:case, node.location)] = arms
      end

      def emit_loop(node, type)
        cond_tuple = build_tuple(type, node.location)
        @branches[cond_tuple] = {build_tuple(:body, loop_body_location(node)) => 0}
      end

      def build_tuple(type, location)
        id = @next_id
        @next_id += 1
        [type, id, location.start_line, location.start_column, location.end_line, location.end_column]
      end
    end
  end
end
