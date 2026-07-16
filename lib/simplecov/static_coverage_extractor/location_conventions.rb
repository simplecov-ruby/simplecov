# frozen_string_literal: true

module SimpleCov
  module StaticCoverageExtractor
    # The source ranges Ruby's Coverage assigns to branch conditions and
    # arms, resolved from Prism nodes. Simulated entries only ever merge
    # with real entries produced by the running Ruby, and CRuby 3.4
    # changed several of these conventions, so every resolver here emits
    # whichever shape this Ruby's Coverage uses. See issues #1226 / #1233.
    #
    # rubocop:disable Metrics/ModuleLength -- one cohesive home for the
    # per-construct, per-Ruby-version Coverage location conventions;
    # splitting it would scatter closely-related resolvers.
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
      # range; with an empty then body the arm collapses to a zero-width
      # point at the predicate's end — always on a modern `if`, and on
      # legacy Rubies only when the construct is in void position (a
      # trailing statement discards its value). In value (tail) position,
      # legacy Rubies and `unless` fall back to the node's range.
      def if_like_then_location(node, type)
        return node.statements.location if node.statements
        return point_at_end(node.predicate.location) if empty_arm_collapses?(node, type)

        if_like_location(node, type)
      end

      # Resolve the source range Coverage attributes to a real-or-synthetic
      # `:else` arm of an if-like construct. IfNode uses
      # `subsequent` / `consequent` and UnlessNode `else_clause` /
      # `consequent`, both depending on Prism version (resolved to
      # `IF_NODE_SUBSEQUENT_METHOD` / `ELSE_CLAUSE_METHOD` at load time).
      # When neither is present, the synthesized else inherits the
      # condition's range (matches Coverage's convention).
      def if_like_else_location(node, type)
        sub = if_like_subsequent(node)
        return if_like_location(node, type) unless sub
        # An `elsif` arrives as a nested IfNode. Coverage attributes the
        # outer else arm to the clause's own range, not its then body
        # (which is what created phantom unmergeable arms).
        return if_like_location(sub, :if) if sub.is_a?(::Prism::IfNode)
        return sub.statements.location if sub.statements

        empty_else_location(node, sub, type)
      end

      # Location of an empty explicit `else`: a modern `if` uses the
      # else..end span; a legacy Ruby in void position collapses to a point
      # at the `else` keyword's end; otherwise (legacy value position, or
      # `unless`) it uses the condition's range.
      def empty_else_location(node, sub, type)
        return sub.location if !LEGACY_COVERAGE_LOCATIONS && type == :if
        return point_at_end(sub.else_keyword_loc) if LEGACY_COVERAGE_LOCATIONS && !value_position?(node)

        if_like_location(node, type)
      end

      # Arm location for a when/in clause: its body statements, or — when
      # the body is empty — the clause's own range on modern Rubies, a
      # point at the pattern's end for a legacy `in`, and for a legacy
      # `when` a point at the clause's end in void position or the tail
      # convention (keyword through the case's remaining content) in value.
      def case_arm_location(case_node, when_node, when_type)
        return when_node.statements.location if when_node.statements
        return when_node.location unless LEGACY_COVERAGE_LOCATIONS
        return point_at_end(when_node.pattern.location) if when_type == :in
        return point_at_end(when_node.location) unless value_position?(case_node)

        legacy_when_value_location(case_node, when_node)
      end

      def legacy_when_value_location(case_node, when_node)
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
        # A when-clause's own location ends where its body ends (or at its
        # condition when empty), so the whole clause extends the range
        # through trailing EMPTY clauses that have no `statements`.
        content = clauses.drop(index + 1).map(&:location)
        else_statements = case_node.public_send(ELSE_CLAUSE_METHOD)&.statements
        content << else_statements.location if else_statements
        content
      end

      # Resolve the source range Coverage attributes to a synthetic-or-real
      # `:else` arm of a case construct: the body of an explicit else,
      # the case's full range when no else is present, and — for an
      # explicit else with an empty body — the else..end span on modern
      # Rubies or the case's full range on legacy ones.
      def else_arm_location(node)
        else_clause = node.public_send(ELSE_CLAUSE_METHOD)
        return node.location unless else_clause
        return else_clause.statements.location if else_clause.statements
        return else_clause.location unless LEGACY_COVERAGE_LOCATIONS
        # Empty explicit `else`: a point at the `else` keyword's end in void
        # position, the whole case's range in value position.
        return point_at_end(else_clause.else_keyword_loc) unless value_position?(node)

        node.location
      end

      # An empty loop body falls back to the loop's range on modern
      # Rubies and collapses to a point at the predicate's end on legacy
      # ones.
      def loop_body_location(node)
        return legacy_do_while_body_location(node) if LEGACY_COVERAGE_LOCATIONS && begin_modifier_loop?(node)
        return node.statements.location if node.statements
        return point_at_end(node.predicate.location) if LEGACY_COVERAGE_LOCATIONS

        node.location
      end

      # `begin ... end while/until cond` (the do-while form) parses as a
      # while/until whose sole statement is the BeginNode. Modern Coverage
      # attributes the body to that whole `begin ... end` span (which the
      # generic `node.statements.location` already yields), but 3.3 uses
      # the begin's inner statements instead — or a point at the end of
      # the `begin` keyword when the body is empty.
      def begin_modifier_loop?(node)
        node.respond_to?(:begin_modifier?) && node.begin_modifier?
      end

      def legacy_do_while_body_location(node)
        begin_node = node.statements.body.first
        inner = begin_node.statements
        inner ? inner.location : point_at_end(begin_node.begin_keyword_loc)
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

      # The `else`/`elsif` clause of an if-like node, under whichever
      # accessor this Prism version exposes (see the two *_METHOD
      # constants).
      def if_like_subsequent(node)
        node.is_a?(::Prism::IfNode) ? node.public_send(IF_NODE_SUBSEQUENT_METHOD) : node.public_send(ELSE_CLAUSE_METHOD)
      end

      # Whether an empty then arm collapses to a point at the predicate's
      # end. Modern Coverage does this for every `if` (but not `unless`);
      # legacy Coverage does it only in void position, for both.
      def empty_arm_collapses?(node, type)
        return type == :if unless LEGACY_COVERAGE_LOCATIONS

        !value_position?(node)
      end

      # Whether `node` sits in value (method-return) position, which on
      # legacy Rubies keeps an empty arm's range instead of collapsing it
      # to a point. `@value_positions` is computed once per parse by
      # ValuePositions (only on legacy; nil elsewhere, which reads as
      # "value" — the safe, pre-audit default).
      def value_position?(node)
        return true if @value_positions.nil?

        @value_positions.key?(node)
      end
      # simplecov:enable
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
