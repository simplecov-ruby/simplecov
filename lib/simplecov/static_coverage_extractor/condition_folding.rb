# frozen_string_literal: true

module SimpleCov
  module StaticCoverageExtractor
    # Detects the `if` / `unless` / ternary conditions CRuby folds away.
    # When a condition is a statically-known-truthy/falsy literal the
    # compiler eliminates the dead arm and Coverage emits NO branch, so the
    # extractor must not synthesize one either — otherwise the arm is a
    # phantom that no loaded run can ever hit, the same unmergeable-tuple
    # failure mode as #1226 / #1233.
    module ConditionFolding
      # CRuby 3.4 rebuilt the fold on the Prism compiler, and the
      # parse.y-based fold it replaced differed in three observable ways,
      # each pinned by the runtime tuple equivalence battery on CI:
      # `__FILE__` folded on 3.2/3.3 but no longer does; parentheses were
      # transparent for every literal on 3.2 (opacity starts at 3.3); and
      # on 3.2 the dead arm's branch table entries survive the fold —
      # parse.y instrumented branches before eliminating dead code — while
      # its `def`s still never register.
      FOLDS_SOURCE_FILE = Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.4")
      PARENS_ALWAYS_TRANSPARENT = Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.3")
      DEAD_ARM_BRANCHES_SURVIVE = PARENS_ALWAYS_TRANSPARENT

      # Prism node types for the literals that fold. `while` / `until` do
      # NOT fold (`while true` is a real branch), so only the if-like
      # visitors consult this. Regexp and Range literals are excluded on
      # purpose: as conditions they mean `=~ $_` / flip-flop, which
      # Coverage does branch on. `[]`, `{}`, and interpolated strings do
      # not fold either, and `->` folds while a `lambda` call does not —
      # the compiler only folds what it can prove at compile time, and a
      # method named `lambda` proves nothing.
      # simplecov:disable branch — which arm runs is fixed by the running Ruby's version
      STATIC_CONDITION_TYPES = [
        ::Prism::IntegerNode, ::Prism::FloatNode, ::Prism::RationalNode,
        ::Prism::ImaginaryNode, ::Prism::SymbolNode, ::Prism::StringNode,
        ::Prism::TrueNode, ::Prism::FalseNode, ::Prism::NilNode,
        ::Prism::SourceLineNode, ::Prism::SourceEncodingNode, ::Prism::LambdaNode,
        *(::Prism::SourceFileNode if FOLDS_SOURCE_FILE)
      ].freeze
      # simplecov:enable branch

      # The literals whose fold eliminates the *then* side: `if false` /
      # `if nil` keep only the else arm. Every other folded literal is
      # truthy and keeps only the then arm.
      FALSY_CONDITION_TYPES = [::Prism::FalseNode, ::Prism::NilNode].freeze

      # The literals whose fold does NOT see through parentheses: CRuby
      # folds `if nil`, `if "x"`, and `if -> {}` but keeps a real branch
      # for `if (nil)`, `if ("x")`, and `if (-> {})` — verified against
      # Coverage, and pinned by the runtime tuple equivalence battery —
      # while every other literal folds parenthesized or not. `__FILE__`
      # is opaque like other strings on the Rubies that fold it at all.
      # Consulted only when PARENS_ALWAYS_TRANSPARENT is false.
      PAREN_OPAQUE_TYPES = [
        ::Prism::NilNode, ::Prism::StringNode, ::Prism::LambdaNode, ::Prism::SourceFileNode
      ].freeze

    private

      # A truthy verdict keeps the first arm live, a falsy one the
      # second. `visit` is nil-safe, so a missing arm just visits
      # nothing. On 3.2 the dead arm's branch table entries survive the
      # fold (parse.y instrumented branches before eliminating dead
      # code, even inside dead `def` bodies and lambdas) while its
      # methods never register, so the dead arm is visited with method
      # collection suppressed.
      def visit_folded_arms(verdict, truthy_arm, falsy_arm)
        live, dead = verdict == :truthy ? [truthy_arm, falsy_arm] : [falsy_arm, truthy_arm]
        visit(live)
        # simplecov:disable branch — the taken arm is fixed by the running Ruby's version
        visit_dead_arm(dead) if DEAD_ARM_BRANCHES_SURVIVE
        # simplecov:enable branch
      end

      # simplecov:disable — 3.2-only; unreachable on the modern dogfood Ruby
      def visit_dead_arm(arm)
        # Save/restore rather than set/clear: a fold nested inside this
        # dead arm re-enters here (possibly with a nil arm) and must not
        # clear suppression for the rest of the outer dead arm.
        previous = @suppress_methods
        begin
          @suppress_methods = true
          visit(arm)
        ensure
          @suppress_methods = previous
        end
      end
      # simplecov:enable

      # The compiler's verdict on a condition: `:truthy` or `:falsy` when
      # it folds, nil when it doesn't. The verdict decides which arm
      # survives — the compiler eliminates the other arm's entire subtree,
      # so everything inside it (nested branches, methods) must go
      # unvisited too, not just the folded condition's own tuple.
      #
      # Parentheses are transparent to the fold for most literals
      # (`if (1)` folds like `if 1`) but not all — see
      # PAREN_OPAQUE_TYPES. Compound forms (`!true`, `true || x`) are
      # deliberately not folded: `!` never folds, and `||` / `&&`
      # constant-propagation diverges across Ruby versions, so matching
      # it would trade a rare, version-specific gain for real risk.
      def folded_condition(node)
        unwrapped = unwrap_parentheses(node)
        return nil unless foldable?(node, unwrapped)

        FALSY_CONDITION_TYPES.any? { |type| unwrapped.is_a?(type) } ? :falsy : :truthy
      end

      # A folding literal, minus the ones parentheses shield from the
      # fold (`unwrapped` differing from `node` is what says parentheses
      # were seen through).
      def foldable?(node, unwrapped)
        return false unless STATIC_CONDITION_TYPES.any? { |type| unwrapped.is_a?(type) }

        # simplecov:disable — which of these lines runs is fixed by the
        # running Ruby's version: on 3.2 the early return always fires and
        # the opacity check below it is dead code, so it must be excluded
        # from line coverage too, not only branch coverage.
        return true if PARENS_ALWAYS_TRANSPARENT

        unwrapped.equal?(node) || PAREN_OPAQUE_TYPES.none? { |type| unwrapped.is_a?(type) }
        # simplecov:enable
      end

      def unwrap_parentheses(node)
        # @type var current: untyped
        current = node
        while current.is_a?(::Prism::ParenthesesNode)
          body = current.body
          break unless body.is_a?(::Prism::StatementsNode) && body.body.size == 1

          current = body.body.first
        end
        current
      end
    end
  end
end
