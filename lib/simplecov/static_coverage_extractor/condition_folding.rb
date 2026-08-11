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
      # Prism node types for the literals that fold. `while` / `until` do
      # NOT fold (`while true` is a real branch), so only the if-like
      # visitors consult this. Regexp and Range literals are excluded on
      # purpose: as conditions they mean `=~ $_` / flip-flop, which
      # Coverage does branch on. `[]`, `{}`, interpolated strings, and
      # `__FILE__` do not fold either, and `->` folds while a `lambda`
      # call does not — the compiler only folds what it can prove at
      # compile time, and a method named `lambda` proves nothing.
      STATIC_CONDITION_TYPES = [
        ::Prism::IntegerNode, ::Prism::FloatNode, ::Prism::RationalNode,
        ::Prism::ImaginaryNode, ::Prism::SymbolNode, ::Prism::StringNode,
        ::Prism::TrueNode, ::Prism::FalseNode, ::Prism::NilNode,
        ::Prism::SourceLineNode, ::Prism::SourceEncodingNode, ::Prism::LambdaNode
      ].freeze

      # The literals whose fold eliminates the *then* side: `if false` /
      # `if nil` keep only the else arm. Every other folded literal is
      # truthy and keeps only the then arm.
      FALSY_CONDITION_TYPES = [::Prism::FalseNode, ::Prism::NilNode].freeze

      # The literals whose fold does NOT see through parentheses: CRuby
      # folds `if nil`, `if "x"`, and `if -> {}` but keeps a real branch
      # for `if (nil)`, `if ("x")`, and `if (-> {})` — verified against
      # Coverage, and pinned by the runtime tuple equivalence battery —
      # while every other literal folds parenthesized or not.
      PAREN_OPAQUE_TYPES = [
        ::Prism::NilNode, ::Prism::StringNode, ::Prism::LambdaNode, ::Prism::SourceFileNode
      ].freeze

      # The scalar literals the compiler treats as fully static: a
      # multi-statement paren condition (`if (1; 2)`) folds by its last
      # expression only when every leading statement is eliminated when
      # discarded, and these — bare or composing an Array/Hash/Range —
      # always are. Pinned against real Coverage on 3.4 and 4.0.
      STATIC_LITERAL_LEAF_TYPES = [
        ::Prism::IntegerNode, ::Prism::FloatNode, ::Prism::RationalNode,
        ::Prism::ImaginaryNode, ::Prism::StringNode, ::Prism::SymbolNode,
        ::Prism::TrueNode, ::Prism::FalseNode, ::Prism::NilNode,
        ::Prism::SourceLineNode, ::Prism::SourceFileNode, ::Prism::SourceEncodingNode, ::Prism::RegularExpressionNode
      ].freeze

      # Non-literal reads that are also eliminated when discarded.
      # Anything that can raise or run hooks (constants, globals, calls,
      # writes) is never eliminated and keeps the branch real.
      ELIMINABLE_READ_TYPES = [
        ::Prism::SelfNode, ::Prism::LocalVariableReadNode,
        ::Prism::InstanceVariableReadNode, ::Prism::DefinedNode
      ].freeze

    private

      # A truthy verdict keeps the first arm live, a falsy one the
      # second. `visit` is nil-safe, so a missing arm just visits
      # nothing. The compiler eliminates the dead arm's entire subtree,
      # so it goes unvisited.
      def visit_folded_arms(verdict, truthy_arm, falsy_arm)
        visit(verdict == :truthy ? truthy_arm : falsy_arm)
      end

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

        unwrapped.equal?(node) || PAREN_OPAQUE_TYPES.none? { |type| unwrapped.is_a?(type) }
      end

      # Parentheses are transparent to the fold, and a multi-statement
      # body (`if (1; 2)`) folds by its LAST expression — but only when
      # the compiler eliminates every leading statement. Stopping at
      # multi-statement bodies synthesized a phantom then/else pair no
      # real run can ever hit.
      def unwrap_parentheses(node)
        # @type var current: untyped
        current = node
        while current.is_a?(::Prism::ParenthesesNode)
          body = current.body
          break unless body.is_a?(::Prism::StatementsNode) && !body.body.empty?

          statements = body.body
          break unless statements.take(statements.size - 1).all? { |leading| eliminable_when_discarded?(leading) }

          current = statements.last
        end
        current
      end

      # Whether the compiler compiles `node` to nothing when its value is
      # discarded.
      def eliminable_when_discarded?(node)
        return true if static_container_literal?(node)
        return true if ELIMINABLE_READ_TYPES.any? { |type| node.is_a?(type) }

        node.is_a?(::Prism::ParenthesesNode) &&
          node.body.is_a?(::Prism::StatementsNode) &&
          node.body.body.all? { |statement| eliminable_when_discarded?(statement) }
      end

      # A scalar literal leaf, or an Array/Hash/Range whose contents are
      # themselves fully static literals (`[1]` is eliminated when
      # discarded, `[x]` is not).
      def static_container_literal?(node)
        return true if STATIC_LITERAL_LEAF_TYPES.any? { |type| node.is_a?(type) }

        static_container?(node)
      end

      # The container dispatch, exercised directly by the predicate specs.
      def static_container?(node)
        case node
        when ::Prism::ArrayNode then static_array_literal?(node)
        when ::Prism::HashNode  then static_hash_literal?(node)
        when ::Prism::RangeNode then static_range_literal?(node)
        else false
        end
      end

      def static_array_literal?(node)
        node.elements.all? { |element| static_container_literal?(element) }
      end

      def static_hash_literal?(node)
        node.elements.all? do |element|
          element.is_a?(::Prism::AssocNode) &&
            static_container_literal?(element.key) && static_container_literal?(element.value)
        end
      end

      def static_range_literal?(node)
        [node.left, node.right].all? { |bound| bound.nil? || static_container_literal?(bound) }
      end
    end
  end
end
