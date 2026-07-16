# frozen_string_literal: true

module SimpleCov
  module StaticCoverageExtractor
    # The source ranges Ruby's Coverage assigns to branch conditions and
    # arms, resolved from Prism nodes. Simulated entries only ever merge
    # with real entries produced by the running Ruby, and CRuby 3.4
    # changed several of these conventions, so every resolver here emits
    # whichever shape this Ruby's Coverage uses. See issue #1226.
    module LocationConventions
      LEGACY_COVERAGE_LOCATIONS = Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.4")

      # A zero-width stand-in for Prism locations, for the arms Coverage
      # anchors to a point rather than a range.
      PointLocation = Data.define(:start_line, :start_column, :end_line, :end_column)

    private

      # simplecov:disable
      # Which arm of each conditional below runs is fixed by the running
      # Ruby's version, so no single process can cover both sides, and
      # the legacy-only helpers are unreachable on modern Rubies (and
      # vice versa). The "runtime tuple equivalence" spec exercises this
      # module against real Coverage output on every CI Ruby.

      # The range Coverage assigns to an if-like node itself. Modern
      # CRuby uses the node's full source range for every form; 3.2/3.3
      # end an `elsif` clause's range at its last content instead of the
      # shared `end` keyword the clause doesn't own.
      def if_like_location(node, type)
        return node.location unless LEGACY_COVERAGE_LOCATIONS && type == :if && elsif_node?(node)

        content_end = legacy_content_end(node)
        PointLocation.new(
          start_line: node.location.start_line, start_column: node.location.start_column,
          end_line: content_end.end_line, end_column: content_end.end_column
        )
      end

      def elsif_node?(node)
        keyword = node.if_keyword_loc
        !keyword.nil? && keyword.slice == "elsif"
      end

      # Where an if/elsif chain's content ends, for the legacy range
      # convention: the deepest trailing clause's statements, or that
      # clause's predicate / `else` keyword when its body is empty.
      def legacy_content_end(node)
        tail = node
        while tail.is_a?(::Prism::IfNode)
          sub = tail.public_send(IF_NODE_SUBSEQUENT_METHOD)
          break unless sub

          tail = sub
        end
        return (tail.statements || tail.predicate).location if tail.is_a?(::Prism::IfNode)

        tail.statements ? tail.statements.location : tail.else_keyword_loc
      end

      # Location of the then arm. Coverage uses the body statements'
      # range; a modern (3.4+) `if` with an empty then body collapses the
      # arm to a zero-width point at the predicate's end, while `unless`
      # and legacy Rubies fall back to the node's range.
      def if_like_then_location(node, type)
        return node.statements.location if node.statements
        return if_like_location(node, type) if LEGACY_COVERAGE_LOCATIONS || type != :if

        point_at_end(node.predicate.location)
      end

      # Resolve the source range Coverage attributes to a real-or-synthetic
      # `:else` arm of an if-like construct. IfNode uses
      # `subsequent` / `consequent` depending on Prism version (resolved
      # to `IF_NODE_SUBSEQUENT_METHOD` at load time); UnlessNode uses
      # `else_clause`. When neither is present, the synthesized else
      # inherits the condition's range (matches Coverage's convention).
      def if_like_else_location(node, type)
        sub = node.is_a?(::Prism::IfNode) ? node.public_send(IF_NODE_SUBSEQUENT_METHOD) : node.else_clause
        return if_like_location(node, type) unless sub
        # An `elsif` arrives as a nested IfNode. Coverage attributes the
        # outer else arm to the clause's own range, not its then body
        # (which is what created phantom unmergeable arms).
        return if_like_location(sub, :if) if sub.is_a?(::Prism::IfNode)
        return sub.statements.location if sub.statements

        # Empty explicit else: a modern `if` uses the else..end span,
        # while `unless` and legacy Rubies use the condition's range.
        return sub.location if !LEGACY_COVERAGE_LOCATIONS && type == :if

        if_like_location(node, type)
      end

      # Arm location for a when/in clause: its body statements, or —
      # when the body is empty — the clause's own range on modern Rubies,
      # and on legacy Rubies a point at the pattern's end for `in`, or
      # the keyword through the case's remaining trailing content for
      # `when` (the same tail convention as legacy elsif ranges).
      def case_arm_location(case_node, when_node, when_type)
        return when_node.statements.location if when_node.statements
        return when_node.location unless LEGACY_COVERAGE_LOCATIONS
        return point_at_end(when_node.pattern.location) if when_type == :in

        tail_end = legacy_case_tail_end(case_node, when_node)
        PointLocation.new(
          start_line: when_node.location.start_line, start_column: when_node.location.start_column,
          end_line: tail_end.end_line, end_column: tail_end.end_column
        )
      end

      # The last body content in the case after `when_node`, falling
      # back to the clause's final condition value.
      def legacy_case_tail_end(case_node, when_node)
        following_case_content(case_node, when_node).last ||
          (when_node.conditions.last || when_node).location
      end

      def following_case_content(case_node, when_node)
        clauses = case_node.conditions
        index = clauses.index { |clause| clause.equal?(when_node) } || 0
        bodies = clauses.drop(index + 1).filter_map { |clause| clause.statements&.location }
        else_statements = case_node.else_clause&.statements
        bodies << else_statements.location if else_statements
        bodies
      end

      # Resolve the source range Coverage attributes to a synthetic-or-real
      # `:else` arm of a case construct: the body of an explicit else,
      # the case's full range when no else is present, and — for an
      # explicit else with an empty body — the else..end span on modern
      # Rubies or the case's full range on legacy ones.
      def else_arm_location(node)
        return node.location unless node.else_clause
        return node.else_clause.statements.location if node.else_clause.statements

        LEGACY_COVERAGE_LOCATIONS ? node.location : node.else_clause.location
      end

      # An empty loop body falls back to the loop's range on modern
      # Rubies and collapses to a point at the predicate's end on legacy
      # ones.
      def loop_body_location(node)
        return node.statements.location if node.statements
        return point_at_end(node.predicate.location) if LEGACY_COVERAGE_LOCATIONS

        node.location
      end

      # Coverage's safe-navigation branch spans the receiver through the
      # end of the call's arguments (or just the message when there are
      # none), but never includes a trailing block: `x&.foo { ... }` and
      # `x&.foo(1) { ... }` both end exactly where `x&.foo` / `x&.foo(1)`
      # would without the block. `node.location` includes an attached
      # block, so build the end position from `closing_loc` (closing
      # paren) / `arguments` (paren-less args) / `message_loc` instead.
      # This convention is the same on legacy and modern Rubies. See
      # issue #1233.
      def safe_navigation_location(node)
        end_loc = node.closing_loc || node.arguments&.location || node.message_loc
        PointLocation.new(
          start_line: node.location.start_line, start_column: node.location.start_column,
          end_line: end_loc.end_line, end_column: end_loc.end_column
        )
      end

      def point_at_end(location)
        PointLocation.new(
          start_line: location.end_line, start_column: location.end_column,
          end_line: location.end_line, end_column: location.end_column
        )
      end
      # simplecov:enable
    end
  end
end
