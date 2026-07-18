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
      # Coverage does branch on.
      STATIC_CONDITION_TYPES = [
        ::Prism::IntegerNode, ::Prism::FloatNode, ::Prism::RationalNode,
        ::Prism::ImaginaryNode, ::Prism::SymbolNode, ::Prism::StringNode,
        ::Prism::TrueNode, ::Prism::FalseNode, ::Prism::NilNode
      ].freeze

    private

      # Parentheses are transparent to the fold (`if (1)` folds like
      # `if 1`), so see through a single parenthesized expression. Compound
      # forms (`!true`, `true || x`) are deliberately not folded: `!` never
      # folds, and `||` / `&&` constant-propagation diverges across Ruby
      # versions, so matching it would trade a rare, version-specific gain
      # for real risk.
      def static_condition?(node)
        node = unwrap_parentheses(node)
        STATIC_CONDITION_TYPES.any? { |type| node.is_a?(type) }
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
