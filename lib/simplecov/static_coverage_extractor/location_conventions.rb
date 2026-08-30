# frozen_string_literal: true

require_relative "prism_compat"

module SimpleCov
  module StaticCoverageExtractor
    # The source ranges Ruby's Coverage assigns to branch conditions and
    # arms, resolved from Prism nodes. Simulated entries only ever merge
    # with real entries produced by the running Ruby, and CRuby 3.4
    # changed several of these conventions, so every resolver here emits
    # whichever shape this Ruby's Coverage uses. See issues #1226 / #1233.
    #
    module LocationConventions
      LEGACY_COVERAGE_LOCATIONS = Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.4")

      # Every resolver here answers a source range: a Prism node, one of
      # its locations, or the point below. All three answer the four
      # position accessors the emitted tuples are built from, and a node
      # answers them with its own location's, so whichever is nearest to
      # hand is what gets returned.
      #
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
        return node unless LEGACY_COVERAGE_LOCATIONS && type.equal?(:if) && elsif_node?(node)

        span(node, legacy_content_end(node))
      end

      def elsif_node?(node)
        keyword = node.if_keyword_loc
        !keyword.nil? && keyword.slice.eql?("elsif")
      end

      # Where an if/elsif chain's content ends, for the legacy range
      # convention: the deepest trailing clause's statements, or that
      # clause's predicate / `else` keyword when its body is empty.
      def legacy_content_end(node)
        tail = node
        while tail.instance_of?(Prism::IfNode)
          sub = PrismCompat.subsequent(tail)
          break unless sub

          tail = sub
        end
        return tail.statements || tail.predicate if tail.instance_of?(Prism::IfNode)

        tail.statements || tail.else_keyword_loc
      end

      # Location of the then arm. Coverage uses the body statements'
      # range; with an empty then body the arm collapses to a zero-width
      # point at the predicate's end — always on a modern `if`, and on
      # legacy Rubies only when the construct is in void position (a
      # trailing statement discards its value). In value (tail) position,
      # legacy Rubies and `unless` fall back to the node's range.
      def if_like_then_location(node, type)
        return node.statements if node.statements
        return point_at_end(node.predicate) if empty_arm_collapses?(node, type)

        if_like_location(node, type)
      end

      # Resolve the source range Coverage attributes to a real-or-synthetic
      # `:else` arm of an if-like construct (`PrismCompat` hides the
      # per-Prism-version accessor split). When no else/elsif is present,
      # the synthesized else inherits the condition's range (matches
      # Coverage's convention).
      def if_like_else_location(node, type)
        sub = PrismCompat.subsequent(node)
        return if_like_location(node, type) unless sub
        # An `elsif` arrives as a nested IfNode. Coverage attributes the
        # outer else arm to the clause's own range, not its then body
        # (which is what created phantom unmergeable arms).
        return if_like_location(sub, :if) if sub.instance_of?(Prism::IfNode)
        return sub.statements if sub.statements

        empty_else_location(node, sub, type)
      end

      # Location of an empty explicit `else`: a modern `if` uses the
      # else..end span; a legacy Ruby in void position collapses to a point
      # at the `else` keyword's end; otherwise (legacy value position, or
      # `unless`) it uses the condition's range.
      def empty_else_location(node, sub, type)
        return sub if !LEGACY_COVERAGE_LOCATIONS && type.equal?(:if)
        # Void position is a legacy distinction: a Ruby that does not
        # need the value-position pass answers every node as value.
        return point_at_end(sub.else_keyword_loc) unless value_position?(node)

        if_like_location(node, type)
      end

      # Arm location for a when/in clause: its body statements, or — when
      # the body is empty — the clause's own range on modern Rubies, a
      # point at the pattern's end for a legacy `in`, and for a legacy
      # `when` a point at the clause's end in void position or the tail
      # convention (keyword through the case's remaining content) in value.
      def case_arm_location(case_node, when_node, when_type)
        return when_node.statements if when_node.statements
        return when_node unless LEGACY_COVERAGE_LOCATIONS
        return point_at_end(when_node.pattern) if when_type.equal?(:in)
        return point_at_end(when_node) unless value_position?(case_node)

        legacy_when_value_location(case_node, when_node)
      end

      def legacy_when_value_location(case_node, when_node)
        span(when_node, legacy_case_tail_end(case_node, when_node))
      end

      # The last body content in the case after `when_node`, falling
      # back to the clause's final condition value. Only a `when` reaches
      # here, and a `when` always carries at least one condition.
      def legacy_case_tail_end(case_node, when_node)
        following_case_content(case_node, when_node).last || when_node.conditions.last
      end

      def following_case_content(case_node, when_node)
        clauses = case_node.conditions
        # The clause is always one of the case's own, so the index is
        # always found. A when-clause's own location ends where its body
        # ends (or at its condition when empty), so the whole clause
        # extends the range through trailing EMPTY clauses that have no
        # `statements`.
        index = clauses.index { |clause| clause.equal?(when_node) }
        content = clauses.drop(index + 1)
        else_statements = PrismCompat.else_clause(case_node)&.statements
        content += [else_statements] if else_statements
        content
      end

      # Resolve the source range Coverage attributes to a synthetic-or-real
      # `:else` arm of a case construct: the body of an explicit else,
      # the case's full range when no else is present, and — for an
      # explicit else with an empty body — the else..end span on modern
      # Rubies or the case's full range on legacy ones.
      def else_arm_location(node)
        else_clause = PrismCompat.else_clause(node)
        return node unless else_clause
        return else_clause.statements if else_clause.statements
        return else_clause unless LEGACY_COVERAGE_LOCATIONS
        # Empty explicit `else`: a point at the `else` keyword's end in void
        # position, the whole case's range in value position.
        return point_at_end(else_clause.else_keyword_loc) unless value_position?(node)

        node
      end

      # An empty loop body falls back to the loop's range on modern
      # Rubies and collapses to a point at the predicate's end on legacy
      # ones.
      def loop_body_location(node)
        return legacy_do_while_body_location(node) if LEGACY_COVERAGE_LOCATIONS && begin_modifier_loop?(node)
        return node.statements if node.statements
        return point_at_end(node.predicate) if LEGACY_COVERAGE_LOCATIONS

        node
      end

      # `begin ... end while/until cond` (the do-while form) parses as a
      # while/until whose sole statement is the BeginNode. Modern Coverage
      # attributes the body to that whole `begin ... end` span (which the
      # generic `node.statements.location` already yields), but 3.3 uses
      # the begin's inner statements instead — or a point at the end of
      # the `begin` keyword when the body is empty.
      # The accessor arrived in Prism 0.25, and this gem supports older
      # ones, where nothing answers the question.
      def begin_modifier_loop?(node)
        node.respond_to?(:begin_modifier?) && node.begin_modifier?
      end

      def legacy_do_while_body_location(node)
        # The do-while's sole statement is the `begin` block itself.
        begin_node, = node.statements.body
        inner = begin_node.statements
        inner || point_at_end(begin_node.begin_keyword_loc)
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
        span(node, node.closing_loc || node.arguments || node.message_loc)
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

      # Whether an empty then arm collapses to a point at the predicate's
      # end. Modern Coverage does this for every `if` (but not `unless`);
      # legacy Coverage does it only in void position, for both.
      def empty_arm_collapses?(node, type)
        return type.equal?(:if) unless LEGACY_COVERAGE_LOCATIONS

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
  end
end
