# frozen_string_literal: true

module SimpleCov
  module StaticCoverageExtractor
    # Detects the `if` / `unless` / ternary conditions CRuby folds away. When a
    # condition is a statically-known-truthy/falsy literal the compiler
    # eliminates the dead arm and Coverage emits no branch, so the extractor
    # must not synthesize one either: the arm would be a phantom no loaded run
    # can hit, the same unmergeable-tuple failure as #1226 / #1233.
    module ConditionFolding
      # CRuby 3.4 rebuilt the fold on the Prism compiler, and the parse.y fold it
      # replaced differed in three observable ways: `__FILE__` folded on
      # 3.2/3.3; parentheses were transparent for every literal on 3.2; and on
      # 3.2 the dead arm's branch table entries survive the fold while its
      # `def`s still never register.
      FOLDS_SOURCE_FILE = Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.4")
      PARENS_ALWAYS_TRANSPARENT = Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.3")
      DEAD_ARM_BRANCHES_SURVIVE = PARENS_ALWAYS_TRANSPARENT
      # Container literals in discarded position are eliminated from 3.3 on, but
      # 3.3's compile.c elides a container whose contents are merely
      # effect-free (`[x]`), while the Prism compiler demands fully static
      # literals (`[1]` goes, `[x]` stays).
      CONTAINER_CONTENTS_NEED_STATIC_LITERALS = !FOLDS_SOURCE_FILE

      # The literals that fold. `while` / `until` do NOT fold (`while true` is a
      # real branch), so only the if-like visitors consult this. Regexp and
      # Range literals are excluded on purpose: as conditions they mean
      # `=~ $_` / flip-flop, which Coverage does branch on. `[]`, `{}`, and
      # interpolated strings do not fold either, and `->` folds while a
      # `lambda` call does not: a method named `lambda` proves nothing.
      # simplecov:disable branch — which arm runs is fixed by the running Ruby's version
      STATIC_CONDITION_TYPES = [
        ::Prism::IntegerNode, ::Prism::FloatNode, ::Prism::RationalNode,
        ::Prism::ImaginaryNode, ::Prism::SymbolNode, ::Prism::StringNode,
        ::Prism::TrueNode, ::Prism::FalseNode, ::Prism::NilNode,
        ::Prism::SourceLineNode, ::Prism::SourceEncodingNode, ::Prism::LambdaNode,
        *(::Prism::SourceFileNode if FOLDS_SOURCE_FILE)
      ].freeze
      # simplecov:enable branch

      FALSY_CONDITION_TYPES = [::Prism::FalseNode, ::Prism::NilNode].freeze

      # CRuby folds `if nil`, `if "x"`, and `if -> {}` but keeps a real branch
      # for `if (nil)`, `if ("x")`, and `if (-> {})`, while every other literal
      # folds parenthesized or not. Consulted only when parentheses are not
      # always transparent.
      PAREN_OPAQUE_TYPES = [
        ::Prism::NilNode, ::Prism::StringNode, ::Prism::LambdaNode, ::Prism::SourceFileNode
      ].freeze

      # A multi-statement paren condition (`if (1; 2)`) folds by its last
      # expression only when every leading statement is eliminated when
      # discarded, and these always are, bare or composing an Array/Hash/Range.
      STATIC_LITERAL_LEAF_TYPES = [
        ::Prism::IntegerNode, ::Prism::FloatNode, ::Prism::RationalNode,
        ::Prism::ImaginaryNode, ::Prism::StringNode, ::Prism::SymbolNode,
        ::Prism::TrueNode, ::Prism::FalseNode, ::Prism::NilNode,
        ::Prism::SourceLineNode, ::Prism::SourceFileNode, ::Prism::SourceEncodingNode, ::Prism::RegularExpressionNode
      ].freeze

      # `self` is eliminated by every supported compiler; local/ivar/defined?
      # elimination arrived with the Prism-era compilers. Anything that can
      # raise or run hooks is never eliminated and keeps the branch real.
      PRISM_ERA_ELIMINABLE_READS = [
        ::Prism::LocalVariableReadNode, ::Prism::InstanceVariableReadNode, ::Prism::DefinedNode
      ].freeze

      # simplecov:disable branch — which arm runs is fixed by the running Ruby's version
      ELIMINABLE_READ_TYPES = [
        ::Prism::SelfNode,
        *(PRISM_ERA_ELIMINABLE_READS unless PARENS_ALWAYS_TRANSPARENT)
      ].freeze
      # simplecov:enable branch

      private

      # On 3.2 the dead arm's branch table entries survive the fold (parse.y
      # instrumented branches before eliminating dead code) while its methods
      # never register, so the dead arm is visited with method collection
      # suppressed.
      def visit_folded_arms(verdict, truthy_arm, falsy_arm)
        live, dead = verdict.equal?(:truthy) ? [truthy_arm, falsy_arm] : [falsy_arm, truthy_arm]
        visit(live)
        visit_dead_arm(dead) if DEAD_ARM_BRANCHES_SURVIVE
      end

      def visit_dead_arm(arm)
        # Save/restore rather than set/clear: a fold nested inside this dead arm
        # re-enters here and must not clear suppression for the rest of it.
        previous = @suppress_methods
        begin
          @suppress_methods = true
          visit(arm)
        ensure
          @suppress_methods = previous
        end
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

        return true if PARENS_ALWAYS_TRANSPARENT

        unwrapped.equal?(node) || PAREN_OPAQUE_TYPES.none? { |type| unwrapped.instance_of?(type) }
      end

      # A multi-statement body (`if (1; 2)`) folds by its LAST expression, but
      # only when the compiler eliminates every leading statement. Stopping at
      # multi-statement bodies synthesized a phantom then/else pair.
      def unwrap_parentheses(node)
        # @type var current: untyped
        current = node
        while current.instance_of?(Prism::ParenthesesNode)
          # Empty parentheses carry no statements node at all, so a
          # body that is one always holds at least one statement.
          body = current.body
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
        return false if PARENS_ALWAYS_TRANSPARENT

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
        node.elements.all? { |element| container_contents_eliminable?(element) }
      end

      def static_hash_literal?(node)
        node.elements.all? do |element|
          element.instance_of?(Prism::AssocNode) &&
            container_contents_eliminable?(element.key) && container_contents_eliminable?(element.value)
        end
      end

      def static_range_literal?(node)
        [node.left, node.right].all? { |bound| bound.nil? || container_contents_eliminable?(bound) }
      end

      def container_contents_eliminable?(node)
        CONTAINER_CONTENTS_NEED_STATIC_LITERALS ? static_container_literal?(node) : eliminable_when_discarded?(node)
      end
    end
  end
end
