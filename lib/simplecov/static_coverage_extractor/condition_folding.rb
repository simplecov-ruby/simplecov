# frozen_string_literal: true

module SimpleCov
  module StaticCoverageExtractor
    # Detects the `if` / `unless` / ternary conditions CRuby folds away. When a
    # condition is a statically-known-truthy/falsy literal the compiler
    # eliminates the dead arm and Coverage emits no branch, so the extractor
    # must not synthesize one either: the arm would be a phantom no loaded run
    # can hit, the same unmergeable-tuple failure as #1226 / #1233.
    module ConditionFolding
      # The literals that fold. `while` / `until` do NOT fold (`while true` is a
      # real branch), so only the if-like visitors consult this. Regexp and
      # Range literals are excluded on purpose: as conditions they mean
      # `=~ $_` / flip-flop, which Coverage does branch on. `[]`, `{}`,
      # interpolated strings, and `__FILE__` do not fold either, and `->` folds
      # while a `lambda` call does not: a method named `lambda` proves nothing.
      STATIC_CONDITION_TYPES = [
        Prism::IntegerNode, Prism::FloatNode, Prism::RationalNode,
        Prism::ImaginaryNode, Prism::SymbolNode, Prism::StringNode,
        Prism::TrueNode, Prism::FalseNode, Prism::NilNode,
        Prism::SourceLineNode, Prism::SourceEncodingNode, Prism::LambdaNode
      ].freeze

      FALSY_CONDITION_TYPES = [Prism::FalseNode, Prism::NilNode].freeze

      # CRuby folds `if nil`, `if "x"`, and `if -> {}` but keeps a real branch
      # for `if (nil)`, `if ("x")`, and `if (-> {})`, while every other literal
      # folds parenthesized or not.
      PAREN_OPAQUE_TYPES = [
        Prism::NilNode, Prism::StringNode, Prism::LambdaNode, Prism::SourceFileNode
      ].freeze

      # A multi-statement paren condition (`if (1; 2)`) folds by its last
      # expression only when every leading statement is eliminated when
      # discarded, and these always are, bare or composing an Array/Hash/Range.
      STATIC_LITERAL_LEAF_TYPES = [
        Prism::IntegerNode, Prism::FloatNode, Prism::RationalNode,
        Prism::ImaginaryNode, Prism::StringNode, Prism::SymbolNode,
        Prism::TrueNode, Prism::FalseNode, Prism::NilNode,
        Prism::SourceLineNode, Prism::SourceFileNode, Prism::SourceEncodingNode, Prism::RegularExpressionNode
      ].freeze

      # Non-literal reads that are also eliminated when discarded. Anything that
      # can raise or run hooks is never eliminated and keeps the branch real.
      ELIMINABLE_READ_TYPES = [
        Prism::SelfNode, Prism::LocalVariableReadNode,
        Prism::InstanceVariableReadNode, Prism::DefinedNode
      ].freeze

      private

      # `visit` is nil-safe, so a missing arm just visits nothing.
      def visit_folded_arms(verdict, truthy_arm, falsy_arm)
        visit(verdict.equal?(:truthy) ? truthy_arm : falsy_arm)
      end

      # `:truthy` or `:falsy` when the compiler folds, nil when it doesn't. The
      # compiler eliminates the losing arm's entire subtree, so everything
      # inside it must go unvisited too, not just the folded condition's tuple.
      #
      # Compound forms (`!true`, `true || x`) are deliberately not folded: `!`
      # never folds, and `||` / `&&` constant-propagation diverges across Ruby
      # versions, so matching it would trade a rare gain for real risk.
      def folded_condition(node)
        unwrapped = unwrap_parentheses(node)
        return nil unless foldable?(node, unwrapped)

        (FALSY_CONDITION_TYPES.any? { |type| unwrapped.instance_of?(type) }) ? :falsy : :truthy
      end

      # `unwrapped` differing from `node` is what says parentheses were seen
      # through.
      def foldable?(node, unwrapped)
        return false unless STATIC_CONDITION_TYPES.any? { |type| unwrapped.instance_of?(type) }

        unwrapped.equal?(node) || PAREN_OPAQUE_TYPES.none? { |type| unwrapped.instance_of?(type) }
      end

      # A multi-statement body (`if (1; 2)`) folds by its LAST expression, but
      # only when the compiler eliminates every leading statement. Stopping at
      # multi-statement bodies synthesized a phantom then/else pair.
      def unwrap_parentheses(node)
        # @type var current: untyped
        current = node
        while current.instance_of?(Prism::ParenthesesNode)
          body = current.body
          # Empty parentheses carry no statements node at all, so a
          # body that is one always holds at least one statement.
          break unless body.instance_of?(Prism::StatementsNode)

          statements = body.body
          break unless statements.take(statements.size - 1).all? { |leading| eliminable_when_discarded?(leading) }

          current = statements.last
        end
        current
      end

      def eliminable_when_discarded?(node)
        return true if static_container_literal?(node)
        return true if ELIMINABLE_READ_TYPES.any? { |type| node.instance_of?(type) }

        node.instance_of?(Prism::ParenthesesNode) &&
          node.body.instance_of?(Prism::StatementsNode) &&
          node.body.body.all? { |statement| eliminable_when_discarded?(statement) }
      end

      def static_container_literal?(node)
        return true if STATIC_LITERAL_LEAF_TYPES.any? { |type| node.instance_of?(type) }

        static_container?(node)
      end

      def static_container?(node)
        case node
        when Prism::ArrayNode then static_array_literal?(node)
        when Prism::HashNode then static_hash_literal?(node)
        when Prism::RangeNode then static_range_literal?(node)
        else false
        end
      end

      def static_array_literal?(node)
        node.elements.all? { |element| static_container_literal?(element) }
      end

      def static_hash_literal?(node)
        node.elements.all? do |element|
          element.instance_of?(Prism::AssocNode) &&
            static_container_literal?(element.key) && static_container_literal?(element.value)
        end
      end

      def static_range_literal?(node)
        [node.left, node.right].all? { |bound| bound.nil? || static_container_literal?(bound) }
      end
    end
  end
end
