# frozen_string_literal: true

require_relative "prism_compat"

module SimpleCov
  module StaticCoverageExtractor
    # The source ranges Ruby's Coverage assigns to branch conditions and arms,
    # resolved from Prism nodes. Simulated entries only ever merge with real
    # entries produced by the running Ruby, and CRuby 3.4 changed several of
    # these conventions, so every resolver here emits whichever shape this
    # Ruby's Coverage uses (#1226, #1233). The "runtime tuple equivalence" spec
    # exercises the module against real Coverage output on every CI Ruby, and
    # is the authority on what each resolver should answer.
    #
    module LocationConventions
      LEGACY_COVERAGE_LOCATIONS = Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.4")

      # A zero-width stand-in for Prism locations, for the arms Coverage
      # anchors to a point rather than a range. Resolvers answer whichever of a
      # node, one of its locations, or this is nearest to hand: all three
      # answer the four position accessors the emitted tuples are built from.
      PointLocation = Data.define(:start_line, :start_column, :end_line, :end_column)

    private

      # Which arm of each conditional below runs is fixed by the running Ruby's
      # version, so no single process can cover both sides.

      # 3.2/3.3 end an `elsif` clause's range at its last content rather than
      # at the shared `end` keyword the clause doesn't own.
      def if_like_location(node, type)
        return node unless LEGACY_COVERAGE_LOCATIONS && type.equal?(:if) && elsif_node?(node)

        span(node, legacy_content_end(node))
      end

      def elsif_node?(node)
        keyword = node.if_keyword_loc
        !keyword.nil? && keyword.slice.eql?("elsif")
      end

      # The deepest trailing clause's statements, or that clause's predicate /
      # `else` keyword when its body is empty.
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

      def if_like_then_location(node, type)
        return node.statements if node.statements
        return point_at_end(node.predicate) if empty_arm_collapses?(node, type)

        if_like_location(node, type)
      end

      # With no else/elsif present, the synthesized else inherits the
      # condition's range.
      def if_like_else_location(node, type)
        sub = PrismCompat.subsequent(node)
        return if_like_location(node, type) unless sub
        # An `elsif` arrives as a nested IfNode, and Coverage attributes the
        # outer else arm to the clause's own range, not its then body (which is
        # what created phantom unmergeable arms).
        return if_like_location(sub, :if) if sub.instance_of?(Prism::IfNode)
        return sub.statements if sub.statements

        empty_else_location(node, sub, type)
      end

      def empty_else_location(node, sub, type)
        return sub if !LEGACY_COVERAGE_LOCATIONS && type.equal?(:if)
        # Void position is a legacy distinction: a Ruby that does not need the
        # value-position pass answers every node as value.
        return point_at_end(sub.else_keyword_loc) unless value_position?(node)

        if_like_location(node, type)
      end

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

      # Only a `when` reaches here, and a `when` always carries at least one
      # condition, so the fallback is always available.
      def legacy_case_tail_end(case_node, when_node)
        following_case_content(case_node, when_node).last || when_node.conditions.last
      end

      def following_case_content(case_node, when_node)
        clauses = case_node.conditions
        # A when-clause's own location ends where its body ends (or at its
        # condition when empty), so the whole clause is what extends the range
        # through trailing empty clauses that have no `statements`.
        index = clauses.index { |clause| clause.equal?(when_node) }
        content = clauses.drop(index + 1)
        else_statements = PrismCompat.else_clause(case_node)&.statements
        content += [else_statements] if else_statements
        content
      end

      def else_arm_location(node)
        else_clause = PrismCompat.else_clause(node)
        return node unless else_clause
        return else_clause.statements if else_clause.statements
        return else_clause unless LEGACY_COVERAGE_LOCATIONS
        return point_at_end(else_clause.else_keyword_loc) unless value_position?(node)

        node
      end

      def loop_body_location(node)
        return legacy_do_while_body_location(node) if LEGACY_COVERAGE_LOCATIONS && begin_modifier_loop?(node)
        return node.statements if node.statements
        return point_at_end(node.predicate) if LEGACY_COVERAGE_LOCATIONS

        node
      end

      # The accessor arrived in Prism 0.25, and this gem supports older ones,
      # where nothing answers the question.
      def begin_modifier_loop?(node)
        node.respond_to?(:begin_modifier?) && node.begin_modifier?
      end

      # `begin ... end while cond` parses as a while whose sole statement is
      # the BeginNode. Modern Coverage attributes the body to that whole
      # `begin ... end` span, but 3.3 uses the begin's inner statements.
      def legacy_do_while_body_location(node)
        begin_node, = node.statements.body
        inner = begin_node.statements
        inner || point_at_end(begin_node.begin_keyword_loc)
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

      # Modern Coverage collapses an empty then arm for every `if` but not
      # `unless`; legacy Coverage does it only in void position, for both.
      def empty_arm_collapses?(node, type)
        return type.equal?(:if) unless LEGACY_COVERAGE_LOCATIONS

        !value_position?(node)
      end

      # `@value_positions` is computed once per parse by ValuePositions, and
      # only on legacy Rubies. Nil elsewhere, which reads as "value": the safe,
      # pre-audit default.
      def value_position?(node)
        return true if @value_positions.nil?

        @value_positions.key?(node)
      end
    end
  end
end
