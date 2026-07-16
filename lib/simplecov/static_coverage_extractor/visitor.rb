# frozen_string_literal: true

require_relative "condition_folding"
require_relative "location_conventions"
require_relative "method_collector"
require_relative "value_position"

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

    # The same Prism 1.3 rename hit the `else` accessor on `UnlessNode`,
    # `CaseNode`, and `CaseMatchNode` (all three: `consequent` ->
    # `else_clause`). Ruby 3.3's stdlib Prism (0.19) only exposes
    # `consequent`, so reaching for `else_clause` there raised
    # NoMethodError inside the extractor — `call` swallowed it and the
    # whole file silently fell back to no simulated data for any
    # `unless`/`else` or empty-arm `case`. Resolve the name once, like
    # IF_NODE_SUBSEQUENT_METHOD. All three nodes renamed together, so one
    # constant (probed off CaseNode) covers them.
    ELSE_CLAUSE_METHOD =
      if ::Prism::CaseNode.method_defined?(:else_clause)
        :else_clause
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
      # Source-range resolution, including the per-Ruby-version Coverage
      # conventions. See issue #1226.
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
        @value_positions = nil
      end

      # Entry point for a parsed file. On legacy Rubies the location of an
      # empty branch arm depends on whether its construct is in value
      # (tail) position, so precompute that once for the whole tree before
      # emitting anything. Modern Rubies don't need it (see
      # LocationConventions), so the pass is skipped there.
      def visit_program_node(node)
        # simplecov:disable branch — legacy-only arm; unreachable on the modern dogfood Ruby
        @value_positions = ValuePositions.call(node) if LEGACY_COVERAGE_LOCATIONS
        # simplecov:enable branch
        super
      end

      # `if` / `unless` / postfix-if / postfix-unless / ternary all parse
      # as IfNode (or UnlessNode). Both carry a `then` arm (the
      # statements body) and an optional `subsequent` (an ElseNode for
      # `else`, another IfNode for `elsif`). When the subsequent is
      # missing, Coverage synthesizes a `:else` arm attributed to the
      # whole condition's range — we do the same.
      def visit_if_node(node)
        emit_if_like(node, :if) unless static_condition?(node.predicate)
        super
      end

      def visit_unless_node(node)
        emit_if_like(node, :unless) unless static_condition?(node.predicate)
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

      # One-line pattern matching: `x => pattern` (MatchRequiredNode) and
      # `x in pattern` (MatchPredicateNode). Ruby 3.3's Coverage reports
      # these as a `:case` with an `:in` and an `:else` arm; 3.4 dropped
      # them entirely (no branch), so this is legacy-only. The two forms
      # differ only in where Coverage anchors the synthesized `:else`:
      # `=>` uses the whole expression, `in` uses just the pattern.
      # simplecov:disable branch — legacy-only arms; unreachable on the modern dogfood Ruby
      def visit_match_required_node(node)
        emit_oneline_pattern(node, node.location) if LEGACY_COVERAGE_LOCATIONS
        super
      end

      def visit_match_predicate_node(node)
        emit_oneline_pattern(node, node.pattern.location) if LEGACY_COVERAGE_LOCATIONS
        super
      end
      # simplecov:enable branch

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
        @branches[build_tuple(type, if_like_location(node, type))] = {
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

      # simplecov:disable — legacy-only (3.4 emits no branch for one-line patterns)
      def emit_oneline_pattern(node, else_location)
        @branches[build_tuple(:case, node.location)] = {
          build_tuple(:in, node.pattern.location) => 0,
          build_tuple(:else, else_location) => 0
        }
      end
      # simplecov:enable

      def emit_case_like(node, when_type)
        arms = node.conditions.to_h do |when_node|
          [build_tuple(when_type, case_arm_location(node, when_node, when_type)), 0]
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
