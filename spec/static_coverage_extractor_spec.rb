# frozen_string_literal: true

require "helper"
require "coverage"
require "support/coverage_differential"

RSpec.describe SimpleCov::StaticCoverageExtractor do
  describe ".available?" do
    it "answers exactly true where Prism is loaded, which every stdlib Prism Ruby is" do
      expect(described_class.available?).to be(true)
    end

    it "answers exactly false where Prism never loaded" do
      hide_const("Prism")

      expect(described_class.available?).to be(false)
    end
  end

  describe "#begin_modifier_loop?" do
    let(:visitor) { SimpleCov::StaticCoverageExtractor::Visitor.new }

    it "asks a node that can answer, and answers what it says" do
      expect(visitor.send(:begin_modifier_loop?, double(begin_modifier?: true))).to be(true)
      expect(visitor.send(:begin_modifier_loop?, double(begin_modifier?: false))).to be(false)
    end

    it "answers false on a Prism too old to be asked" do
      expect(visitor.send(:begin_modifier_loop?, double)).to be(false)
    end
  end

  describe ".call" do
    context "when Prism is not available" do
      before { allow(described_class).to receive(:available?).and_return(false) }

      it "returns nil so callers fall back to empty hashes" do
        expect(described_class.call("a = 1\n")).to be_nil
      end

      it "parses nothing at all" do
        allow(Prism).to receive(:parse)

        described_class.call("a = 1\n")

        expect(Prism).not_to have_received(:parse)
      end
    end

    context "when Prism is available", if: described_class.available? do
      it "returns nil on a parse failure" do
        expect(described_class.call("def f(\n")).to be_nil
      end

      it "returns hash-shaped branches and methods on success" do
        result = described_class.call("def f; 1; end\n")
        expect(result.keys).to contain_exactly("branches", "methods")
      end

      it "answers nil rather than raising when the walk itself fails" do
        allow(Prism).to receive(:parse).and_raise(RuntimeError, "unsupported node")

        expect(described_class.call("a = 1\n")).to be_nil
      end

      describe "branch enumeration" do
        def static_branches(source)
          described_class.call(source)["branches"]
        end

        {
          "an if with an else" =>
            ["if a\n  :t\nelse\n  :e\nend\n",
              {[:if, 0, 1, 0, 5, 3] => {[:then, 1, 2, 2, 2, 4] => 0, [:else, 2, 4, 2, 4, 4] => 0}}],

          "an unless with an else" =>
            ["unless a\n  :t\nelse\n  :e\nend\n",
              {[:unless, 0, 1, 0, 5, 3] => {[:then, 1, 2, 2, 2, 4] => 0, [:else, 2, 4, 2, 4, 4] => 0}}],

          "a case with two whens" =>
            ["case a\nwhen 1 then :x\nwhen 2 then :y\nend\n",
              {[:case, 3, 1, 0, 4, 3] =>
                {[:when, 0, 2, 12, 2, 14] => 0, [:when, 1, 3, 12, 3, 14] => 0, [:else, 2, 1, 0, 4, 3] => 0}}],

          "a case with one in arm" =>
            ["case a\nin Integer then :x\nend\n",
              {[:case, 2, 1, 0, 3, 3] => {[:in, 0, 2, 16, 2, 18] => 0, [:else, 1, 1, 0, 3, 3] => 0}}],

          "a while loop" =>
            ["while a\n  :b\nend\n", {[:while, 0, 1, 0, 3, 3] => {[:body, 1, 2, 2, 2, 4] => 0}}],

          "an until loop" =>
            ["until a\n  :b\nend\n", {[:until, 0, 1, 0, 3, 3] => {[:body, 1, 2, 2, 2, 4] => 0}}],

          "a safe navigation call with a block" =>
            ["a&.foo(1) { 2 }\n",
              {[:"&.", 0, 1, 0, 1, 9] => {[:then, 1, 1, 0, 1, 9] => 0, [:else, 2, 1, 0, 1, 9] => 0}}]
        }.each do |description, (source, expected)|
          it "numbers and zeroes every tuple of #{description}" do
            expect(static_branches(source)).to eq(expected)
          end
        end

        it "walks a call node that cannot say whether it is safe navigation" do
          node = Class.new {
            def each_child_node
            end
          }.new
          visitor = described_class::Visitor.new
          visitor.visit_call_node(node)

          expect(visitor.branches).to be_empty
        end

        it "runs no value-position pass where the conventions do not need one" do
          stub_const("#{described_class}::LocationConventions::LEGACY_COVERAGE_LOCATIONS", false)
          allow(described_class::ValuePositions).to receive(:call).and_call_original

          described_class.call("def fx(a)\n  if a\n  end\nend\n")

          expect(described_class::ValuePositions).not_to have_received(:call)
        end

        it "matches Coverage for `if`/`else` block form" do
          src = "x = 1\nif x > 0\n  :a\nelse\n  :b\nend\n"
          static = static_branches(src)
          expect(static.keys.first.first).to eq(:if)
          arms = static.values.first
          expect(arms.keys.map(&:first)).to contain_exactly(:then, :else)
        end

        it "matches Coverage for `case`/`when` block form" do
          src = "x = 1\ncase x\nwhen 1 then :a\nwhen 2 then :b\nend\n"
          static = static_branches(src)
          arms = static.values.first
          expect(arms.keys.map(&:first)).to contain_exactly(:when, :when, :else)
        end

        it "uses the body location for an explicit else in case/when" do
          src = "x = 1\ncase x\nwhen 1 then :a\nelse :b\nend\n"
          static = static_branches(src)
          arms = static.values.first
          else_tuple = arms.keys.find { |k| k.first == :else }
          expect(else_tuple[2]).to eq(4)
        end

        it "matches Coverage for `case`/`in` pattern matching" do
          src = "x = 1\ncase x\nin Integer then :i\nin String then :s\nend\n"
          static = static_branches(src)
          arms = static.values.first
          expect(arms.keys.map(&:first)).to contain_exactly(:in, :in, :else)
        end

        it "matches Coverage for `while` loop body" do
          src = "i = 0\ni += 1 while i < 3\n"
          static = static_branches(src)
          arms = static.values.first
          expect(arms.keys.map(&:first)).to eq([:body])
        end

        it "matches Coverage for `until` loop body" do
          src = "i = 0\ni += 1 until i >= 3\n"
          static = static_branches(src)
          expect(static.keys.first.first).to eq(:until)
          arms = static.values.first
          expect(arms.keys.map(&:first)).to eq([:body])
        end

        it "matches Coverage for `unless` block form" do
          src = "x = 1\nunless x > 0\n  :a\nelse\n  :b\nend\n"
          static = static_branches(src)
          expect(static.keys.first.first).to eq(:unless)
          arms = static.values.first
          expect(arms.keys.map(&:first)).to contain_exactly(:then, :else)
        end

        {
          "an unless" => ["unless a\n  if b\n    :x\n  end\nend\n", %i[unless if]],
          "a while loop" => ["while a\n  if b\n    :x\n  end\nend\n", %i[while if]],
          "an until loop" => ["until a\n  if b\n    :x\n  end\nend\n", %i[until if]]
        }.each do |description, (source, expected)|
          it "descends into #{description}, collecting the branches nested in its body" do
            expect(static_branches(source).keys.map(&:first)).to eq(expected)
          end
        end

        it "handles empty arm bodies (e.g., `if cond then end`)" do
          src = "if x then end\n"
          static = static_branches(src)
          arms = static.values.first
          expect(arms.keys).to all(satisfy { |tuple| tuple[2].is_a?(Integer) })
        end

        it "matches Coverage for postfix `if`" do
          src = "x = 1\n:hit if x > 0\n"
          static = static_branches(src)
          arms = static.values.first
          expect(arms.keys.map(&:first)).to contain_exactly(:then, :else)
        end

        it "matches Coverage for ternary" do
          src = "x = 1\nx > 0 ? :y : :n\n"
          static = static_branches(src)
          arms = static.values.first
          expect(arms.keys.map(&:first)).to contain_exactly(:then, :else)
        end

        it "matches Coverage for safe navigation" do
          src = "x = Object.new\nx&.to_s\n"
          static = static_branches(src)
          expect(static.keys.first.first).to eq(:"&.")
          arms = static.values.first
          expect(arms.keys.map(&:first)).to contain_exactly(:then, :else)
        end

        it "does NOT track `||=` (mirrors Coverage's documented behavior)" do
          src = "@x ||= 1\n"
          expect(static_branches(src)).to be_empty
        end

        it "emits a loop body arm for a do-while (`begin ... end while`)" do
          src = "begin\n  x\nend while y\n"
          arms = static_branches(src).values.first
          expect(arms.keys.map(&:first)).to contain_exactly(:body)
        end

        it "extracts a case/when with an empty arm without crashing" do
          arms = static_branches("case x\nwhen 1\nwhen 2 then :b\nend\n").values.first
          expect(arms.keys.map(&:first)).to contain_exactly(:when, :when, :else)
        end

        it "extracts an unless/else without crashing" do
          arms = static_branches("unless x\n  :a\nelse\n  :b\nend\n").values.first
          expect(arms.keys.map(&:first)).to contain_exactly(:then, :else)
        end

        context "with a constant-folded condition" do
          [
            ["if 1\n  x\nend\n", "integer"],
            ["if true\n  x\nend\n", "true"],
            ["if false\n  x\nelse\n  y\nend\n", "false"],
            ["if nil\n  x\nend\n", "nil"],
            ["if :z\n  x\nend\n", "symbol"],
            ["if 1.5\n  x\nend\n", "float"],
            ["unless true\n  x\nend\n", "unless with literal"],
            ["1 ? x : y\n", "ternary"],
            ["if (1)\n  x\nend\n", "parenthesized literal"],
            ["if __LINE__\n  x\nend\n", "__LINE__"],
            ["if __ENCODING__\n  x\nend\n", "__ENCODING__"],
            ["if -> { x }\n  a\nend\n", "lambda literal"]
          ].each do |src, label|
            it "emits no branch for a #{label} condition" do
              expect(static_branches(src)).to be_empty
            end
          end

          it "still tracks a non-literal condition" do
            expect(static_branches("if a\n  x\nend\n").keys.first.first).to eq(:if)
          end

          it "still tracks `while true` (loops are not folded)" do
            expect(static_branches("while true\n  x\nend\n").keys.first.first).to eq(:while)
          end

          it "still tracks `!true` (negation is not folded)" do
            expect(static_branches("if !true\n  x\nend\n").keys.first.first).to eq(:if)
          end

          it "matches the running compiler's treatment of `__FILE__`" do
            branches = static_branches("if __FILE__\n  x\nend\n")
            if SimpleCov::StaticCoverageExtractor::ConditionFolding::FOLDS_SOURCE_FILE
              expect(branches).to be_empty
            else
              expect(branches.keys.first.first).to eq(:if)
            end
          end

          it "still tracks a `lambda` call (only the `->` literal folds)" do
            expect(static_branches("if lambda { x }\n  a\nend\n").keys.first.first).to eq(:if)
          end

          it "matches the running compiler's paren transparency for `(nil)`, `(\"x\")`, and `(-> {})`" do
            trio = ["if (nil)\n  x\nend\n", "if (\"x\")\n  a\nend\n", "if (-> { x })\n  a\nend\n"]
            if SimpleCov::StaticCoverageExtractor::ConditionFolding::PARENS_ALWAYS_TRANSPARENT
              trio.each { |src| expect(static_branches(src)).to be_empty }
            else
              trio.each { |src| expect(static_branches(src).keys.first.first).to eq(:if) }
            end
          end

          it "folds a multi-statement paren condition with eliminable leading statements" do
            expect(static_branches("if (1; 2)\n  x\nelse\n  y\nend\n")).to be_empty
            expect(static_branches("if (:s; \"t\"; 2)\n  x\nend\n")).to be_empty
            expect(static_branches("if ((1; 2))\n  x\nend\n")).to be_empty
          end

          it "keeps the branch when a leading statement is not eliminable" do
            expect(static_branches("if (a; 2)\n  x\nend\n").keys.first.first).to eq(:if)
            expect(static_branches("if (x = 5; 2)\n  x\nend\n").keys.first.first).to eq(:if)
            expect(static_branches("if ([a]; 2)\n  x\nend\n").keys.first.first).to eq(:if)
            expect(static_branches("if ({a: b}; 2)\n  x\nend\n").keys.first.first).to eq(:if)
          end

          it "keeps the branch when the last statement of a sequence is not a foldable literal" do
            expect(static_branches("if (1; a)\n  x\nend\n").keys.first.first).to eq(:if)
          end

          it "keeps the branch for an empty paren condition" do
            expect(static_branches("if ()\n  x\nend\n").keys.first.first).to eq(:if)
          end

          it "applies paren opacity to the last statement of a sequence" do
            src = "if (1; nil)\n  x\nelse\n  y\nend\n"
            if SimpleCov::StaticCoverageExtractor::ConditionFolding::PARENS_ALWAYS_TRANSPARENT
              expect(static_branches(src)).to be_empty
            else
              expect(static_branches(src).keys.first.first).to eq(:if)
            end
          end

          it "matches the running compiler for version-dependent eliminable leading reads" do
            srcs = ["if (@x; 2)\n  a\nend\n", "if ([1]; 2)\n  a\nend\n",
              "if ({a: 1}; 2)\n  a\nend\n", "if ((3..4); 2)\n  a\nend\n"]
            if SimpleCov::StaticCoverageExtractor::ConditionFolding::PARENS_ALWAYS_TRANSPARENT
              srcs.each { |src| expect(static_branches(src).keys.first.first).to eq(:if) }
            else
              srcs.each { |src| expect(static_branches(src)).to be_empty }
            end
          end

          it "matches the running compiler for a branch nested in a dead then arm" do
            branches = static_branches("if false\n  if a\n    :x\n  end\nend\n")
            if SimpleCov::StaticCoverageExtractor::ConditionFolding::DEAD_ARM_BRANCHES_SURVIVE
              expect(branches.keys.map(&:first)).to eq([:if])
            else
              expect(branches).to be_empty
            end
          end

          it "matches the running compiler for a branch nested in a dead else arm" do
            branches = static_branches("if true\n  :a\nelse\n  if a\n    :x\n  end\nend\n")
            if SimpleCov::StaticCoverageExtractor::ConditionFolding::DEAD_ARM_BRANCHES_SURVIVE
              expect(branches.keys.map(&:first)).to eq([:if])
            else
              expect(branches).to be_empty
            end
          end

          it "emits no method tuple for a def in a dead arm" do
            result = described_class.call("if false\n  def dead_fn\n  end\nend\n")
            expect(result["methods"]).to be_empty
          end

          it "keeps a branch nested in the live arm" do
            expect(static_branches("if true\n  if a\n    :x\n  end\nend\n").keys.first.first).to eq(:if)
          end

          it "keeps a falsy if's elsif chain as a plain if" do
            branches = static_branches("if false\n  :a\nelsif a\n  :b\nend\n")
            expect(branches.keys.map(&:first)).to eq([:if])
          end

          it "keeps the else contents of a folded truthy unless" do
            branches = static_branches("unless true\n  a ? :x : :y\nelse\n  if b\n    :z\n  end\nend\n")
            if SimpleCov::StaticCoverageExtractor::ConditionFolding::DEAD_ARM_BRANCHES_SURVIVE
              expect(branches.keys.map(&:first)).to eq(%i[if if])
            else
              expect(branches.keys.map(&:first)).to eq([:if])
            end
          end

          it "keeps the body contents of a folded falsy unless" do
            branches = static_branches("unless false\n  if b\n    :z\n  end\nelse\n  a ? :x : :y\nend\n")
            if SimpleCov::StaticCoverageExtractor::ConditionFolding::DEAD_ARM_BRANCHES_SURVIVE
              expect(branches.keys.map(&:first)).to eq(%i[if if])
            else
              expect(branches.keys.map(&:first)).to eq([:if])
            end
          end
        end
      end

      describe "container eliminability predicates" do
        def predicate(name, source)
          node = Prism.parse(source).value.statements.body.first
          SimpleCov::StaticCoverageExtractor::Visitor.new.send(name, node)
        end

        it "treats containers of scalar literals as static" do
          expect(predicate(:static_container?, "[1, 2]")).to be true
          expect(predicate(:static_container?, "{a: 1}")).to be true
          expect(predicate(:static_container?, "3..4")).to be true
          expect(predicate(:static_container?, "..4")).to be true
        end

        it "rejects containers with effectful or non-literal contents" do
          expect(predicate(:static_container?, "[foo]")).to be false
          expect(predicate(:static_container?, "{a: foo}")).to be false
          expect(predicate(:static_container?, "{**foo}")).to be false
          expect(predicate(:static_container?, "foo..4")).to be false
          expect(predicate(:static_container?, "foo")).to be false
        end

        it "rejects a container that is only partly literal" do
          expect(predicate(:static_container?, "[1, foo]")).to be false
          expect(predicate(:static_container?, "[foo, 1]")).to be false
          expect(predicate(:static_container?, "{a: 1, b: foo}")).to be false
        end

        it "reads both sides of a hash pair and of a range" do
          expect(predicate(:static_container?, "{foo => 1}")).to be false
          expect(predicate(:static_container?, "{1 => foo}")).to be false
          expect(predicate(:static_container?, "1..foo")).to be false
          expect(predicate(:static_container?, "1..")).to be true
        end

        it "reads an empty container as static" do
          expect(predicate(:static_container?, "[]")).to be true
          expect(predicate(:static_container?, "{}")).to be true
        end

        it "answers about a node that is no container at all" do
          expect(predicate(:static_container?, ":sym")).to be false
        end

        describe "eliminable when discarded" do
          it "counts a literal and a read with nothing behind it" do
            expect(predicate(:eliminable_when_discarded?, "1")).to be true
            expect(predicate(:eliminable_when_discarded?, "self")).to be true
          end

          it "counts out a call, which could do anything" do
            expect(predicate(:eliminable_when_discarded?, "foo(1)")).to be false
          end

          it "sees through parentheses, however many statements they hold" do
            expect(predicate(:eliminable_when_discarded?, "(1)")).to be true
            expect(predicate(:eliminable_when_discarded?, "(1; 2)")).to be true
            expect(predicate(:eliminable_when_discarded?, "((1))")).to be true
          end

          it "counts out parentheses holding anything that is not" do
            expect(predicate(:eliminable_when_discarded?, "(1; foo(1))")).to be false
            expect(predicate(:eliminable_when_discarded?, "(foo(1); 1)")).to be false
          end

          it "counts out parentheses holding nothing" do
            expect(predicate(:eliminable_when_discarded?, "()")).to be false
          end
        end

        describe "unwrapping parentheses" do
          def unwrapped(source)
            predicate(:unwrap_parentheses, source).class.name
          end

          it "sees through parentheses to the literal inside" do
            expect(unwrapped("(1)")).to eq("Prism::IntegerNode")
            expect(unwrapped("((1))")).to eq("Prism::IntegerNode")
          end

          it "takes the last expression when the leading ones compile away" do
            expect(unwrapped("(1; :two)")).to eq("Prism::SymbolNode")
          end

          it "takes a last expression that compiles to something" do
            expect(unwrapped("(1; foo(2))")).to eq("Prism::CallNode")
          end

          it "unwraps a lone statement whatever it compiles to" do
            expect(unwrapped("(foo(1))")).to eq("Prism::CallNode")
          end

          it "stops at a leading statement that compiles to something" do
            expect(unwrapped("(foo(1); 2)")).to eq("Prism::ParenthesesNode")
          end

          it "stops at parentheses holding nothing" do
            expect(unwrapped("()")).to eq("Prism::ParenthesesNode")
          end

          it "leaves a node that is not parenthesized alone" do
            expect(unwrapped("1")).to eq("Prism::IntegerNode")
          end

          it "leaves parentheses holding something other than a statements list alone" do
            parens = Prism.parse("(1)").value.statements.body.first
            odd = parens.copy(body: parens.body.body.first)
            visitor = SimpleCov::StaticCoverageExtractor::Visitor.new
            expect(visitor.send(:unwrap_parentheses, odd)).to equal(odd)
          end
        end

        describe "the folding verdict" do
          it "answers falsy for the literals that keep only the else arm" do
            expect(predicate(:folded_condition, "false")).to eq(:falsy)
            expect(predicate(:folded_condition, "nil")).to eq(:falsy)
          end

          it "answers truthy for every other folding literal" do
            expect(predicate(:folded_condition, "true")).to eq(:truthy)
            expect(predicate(:folded_condition, "1")).to eq(:truthy)
            expect(predicate(:folded_condition, ":sym")).to eq(:truthy)
            expect(predicate(:folded_condition, "-> {}")).to eq(:truthy)
          end

          it "answers nothing for a condition that does not fold" do
            expect(predicate(:folded_condition, "foo")).to be_nil
            expect(predicate(:folded_condition, "!true")).to be_nil
            expect(predicate(:folded_condition, "/re/")).to be_nil
            expect(predicate(:folded_condition, "[]")).to be_nil
          end

          it "sees through parentheses for the literals they do not shield" do
            expect(predicate(:folded_condition, "(1)")).to eq(:truthy)
            expect(predicate(:folded_condition, "(false)")).to eq(:falsy)
          end

          it "declines to fold the literals parentheses shield" do
            shielded = SimpleCov::StaticCoverageExtractor::ConditionFolding::PARENS_ALWAYS_TRANSPARENT
            expect(predicate(:folded_condition, "(nil)")).to eq(shielded ? :falsy : nil)
            expect(predicate(:folded_condition, '("x")')).to eq(shielded ? :truthy : nil)
          end
        end

        describe "the parse.y era conventions" do
          def stub_era(constant, value)
            stub_const("SimpleCov::StaticCoverageExtractor::ConditionFolding::#{constant}", value)
          end

          def paren_pair(source)
            node = Prism.parse(source).value.statements.body.first
            [node, Prism.parse(source.delete("()")).value.statements.body.first]
          end

          it "sees through parentheses for a literal 3.3 shields" do
            stub_era("PARENS_ALWAYS_TRANSPARENT", true)
            visitor = SimpleCov::StaticCoverageExtractor::Visitor.new
            expect(visitor.send(:foldable?, *paren_pair("(nil)"))).to be true
          end

          it "shields that same literal once opacity arrives" do
            stub_era("PARENS_ALWAYS_TRANSPARENT", false)
            visitor = SimpleCov::StaticCoverageExtractor::Visitor.new
            expect(visitor.send(:foldable?, *paren_pair("(nil)"))).to be false
          end

          it "eliminates a container literal once parens are opaque" do
            stub_era("PARENS_ALWAYS_TRANSPARENT", false)
            expect(predicate(:static_container_literal?, "[1, 2]")).to be true
          end

          it "eliminates no container literal" do
            stub_era("PARENS_ALWAYS_TRANSPARENT", true)
            expect(predicate(:static_container_literal?, "[1, 2]")).to be false
            expect(predicate(:static_container_literal?, "1")).to be true
          end

          it "asks only that container contents be effect-free" do
            stub_era("CONTAINER_CONTENTS_NEED_STATIC_LITERALS", false)
            expect(predicate(:container_contents_eliminable?, "self")).to be true
            expect(predicate(:container_contents_eliminable?, "foo(1)")).to be false
          end

          it "asks that they be static literals from 3.4 on" do
            stub_era("CONTAINER_CONTENTS_NEED_STATIC_LITERALS", true)
            expect(predicate(:container_contents_eliminable?, "self")).to be false
            expect(predicate(:container_contents_eliminable?, "1")).to be true
          end

          it "keeps the dead arm's branches and drops its methods" do
            stub_era("DEAD_ARM_BRANCHES_SURVIVE", true)
            result = described_class.call("if true\n  :a\nelse\n  b ? :c : :d\n  def dead_fn\n  end\nend\n")
            expect(result["branches"].keys.map(&:first)).to eq([:if])
            expect(result["methods"]).to be_empty
          end

          it "keeps the dead then arm's branches under a falsy fold" do
            stub_era("DEAD_ARM_BRANCHES_SURVIVE", true)
            result = described_class.call("if false\n  b ? :c : :d\n  def dead_fn\n  end\nelse\n  :a\nend\n")
            expect(result["branches"].keys.map(&:first)).to eq([:if])
            expect(result["methods"]).to be_empty
          end

          it "drops both from 3.3 on" do
            stub_era("DEAD_ARM_BRANCHES_SURVIVE", false)
            result = described_class.call("if true\n  :a\nelse\n  b ? :c : :d\n  def dead_fn\n  end\nend\n")
            expect(result["branches"]).to be_empty
            expect(result["methods"]).to be_empty
          end

          it "keeps methods suppressed after a fold nested in the dead arm" do
            stub_era("DEAD_ARM_BRANCHES_SURVIVE", true)
            result = described_class.call(
              "if true\n  :a\nelse\n  if false\n    :b\n  end\n  def dead_fn\n  end\nend\n"
            )
            expect(result["methods"]).to be_empty
          end

          it "restores collection once the dead arm is behind it" do
            stub_era("DEAD_ARM_BRANCHES_SURVIVE", true)
            result = described_class.call("if true\n  :a\nelse\n  :b\nend\ndef live_fn\nend\n")
            expect(result["methods"].keys.map { |key| key[1] }).to eq([:live_fn])
          end
        end
      end

      describe "runtime tuple equivalence" do
        let(:branch_fixtures) do
          {
            "if_else" => "def fx(a)\n  if a\n    :a\n  else\n    :b\n  end\nend\n",
            "if_no_else" => "def fx(a)\n  if a\n    :a\n  end\nend\n",
            "if_elsif" => "def fx(a)\n  if a == 1\n    :a\n  elsif a == 2\n    :b\n  end\nend\n",
            "if_elsif_else" => "def fx(a)\n  if a == 1\n    :a\n  elsif a == 2\n    :b\n  else\n    :c\n  end\nend\n",
            "if_elsif_elsif_else" =>
            "def fx(a)\n  if a == 1\n    :a\n  elsif a == 2\n    :b\n  elsif a == 3\n    :c\n  " \
            "else\n    :d\n  end\nend\n",
            "elsif_chain_no_else" =>
            "def fx(a)\n  if a == 1\n    :a\n  elsif a == 2\n    :b\n  elsif a == 3\n    :c\n  end\nend\n",
            "elsif_empty_body" => "def fx(a)\n  if a == 1\n    :a\n  elsif a == 2\n  end\nend\n",
            "empty_then" => "def fx(a)\n  if a\n  end\nend\n",
            "empty_then_with_else" => "def fx(a)\n  if a\n  else\n    :b\n  end\nend\n",
            "empty_else" => "def fx(a)\n  if a\n    :a\n  else\n  end\nend\n",
            "empty_both" => "def fx(a)\n  if a\n  else\n  end\nend\n",
            "if_then_end" => "def fx(a)\n  if a then end\nend\n",
            "nested_if_in_else" => "def fx(a, b)\n  if a\n    :a\n  else\n    if b\n      :b\n    end\n  end\nend\n",
            "unless_no_else" => "def fx(a)\n  unless a\n    :a\n  end\nend\n",
            "unless_else" => "def fx(a)\n  unless a\n    :a\n  else\n    :b\n  end\nend\n",
            "unless_empty" => "def fx(a)\n  unless a\n  end\nend\n",
            "unless_empty_else" => "def fx(a)\n  unless a\n    :a\n  else\n  end\nend\n",
            "elsif_else_empty" => "def fx(a)\n  if a == 1\n    :a\n  elsif a == 2\n    :b\n  else\n  end\nend\n",
            "modifier_if" => "def fx(a)\n  :a if a\nend\n",
            "modifier_unless" => "def fx(a)\n  :a unless a\nend\n",
            "ternary" => "def fx(a)\n  a ? :a : :b\nend\n",
            "case_when" => "def fx(a)\n  case a\n  when 1 then :a\n  when 2 then :b\n  end\nend\n",
            "case_when_else" => "def fx(a)\n  case a\n  when 1 then :a\n  else :b\n  end\nend\n",
            "case_when_empty_body" => "def fx(a)\n  case a\n  when 1\n  when 2 then :b\n  end\nend\n",
            "case_when_empty_last" => "def fx(a)\n  case a\n  when 1 then :a\n  when 2\n  end\nend\n",
            "case_empty_else" => "def fx(a)\n  case a\n  when 1 then :a\n  else\n  end\nend\n",
            "case_in" => "def fx(a)\n  case a\n  in Integer then :i\n  in String then :s\n  end\nend\n",
            "case_in_else" => "def fx(a)\n  case a\n  in Integer then :i\n  else :o\n  end\nend\n",
            "case_in_empty_body" => "def fx(a)\n  case a\n  in Integer\n  in String then :s\n  end\nend\n",
            "case_in_empty_last" => "def fx(a)\n  case a\n  in Integer then :i\n  in String\n  end\nend\n",
            "while_block" => "def fx\n  i = 0\n  while i < 3\n    i += 1\n  end\nend\n",
            "while_modifier" => "def fx\n  i = 0\n  i += 1 while i < 3\nend\n",
            "while_empty" => "def fx(a)\n  while a\n  end\nend\n",
            "until_empty" => "def fx(a)\n  until a\n  end\nend\n",
            "until_block" => "def fx\n  i = 0\n  until i >= 3\n    i += 1\n  end\nend\n",
            "safe_navigation" => "def fx(a)\n  a&.to_s\nend\n",
            "safe_navigation_args" => "def fx(a)\n  a&.foo(1)\nend\n",
            "safe_navigation_parenless_args" => "def fx(a)\n  a&.foo 1\nend\n",
            "safe_navigation_block" => "def fx(a)\n  a&.foo { 1 }\nend\n",
            "safe_navigation_args_block" => "def fx(a)\n  a&.foo(1) { 1 }\nend\n",
            "safe_navigation_chain_block" => "def fx(a)\n  a&.foo&.bar { 1 }\nend\n",
            "safe_navigation_chain_args_block" => "def fx(a)\n  a&.foo(1)&.bar(2) { 1 }\nend\n",
            "folded_if_true" => "def fx(a)\n  if true\n    :a\n  else\n    :b\n  end\nend\n",
            "folded_if_int" => "def fx(a)\n  if 1\n    :a\n  end\nend\n",
            "folded_unless_false" => "def fx(a)\n  unless false\n    :a\n  end\nend\n",
            "folded_ternary" => "def fx(a)\n  1 ? :a : :b\nend\n",
            "folded_if_void" => "def fx(a)\n  if true\n    :a\n  end\n  a\nend\n",
            "folded_dead_then_nested" => "def fx(a)\n  if false\n    a ? :x : :y\n  end\nend\n",
            "folded_dead_def_branch" =>
              "def fx(a)\n  if false\n    def dead(x)\n      x ? 1 : 2\n    end\n  end\nend\n",
            "folded_dead_lambda_body" => "def fx(a)\n  if false\n    y = -> { a ? 1 : 2 }\n  end\nend\n",
            "folded_dead_else_nested" => "def fx(a)\n  if true\n    :a\n  else\n    a ? :x : :y\n  end\nend\n",
            "folded_live_then_nested" => "def fx(a)\n  if true\n    a ? :x : :y\n  end\nend\n",
            "folded_elsif_survives" => "def fx(a)\n  if false\n    :a\n  elsif a\n    :b\n  end\nend\n",
            "folded_midchain_elsif" =>
              "def fx(a)\n  if a\n    1\n  elsif true\n    2\n  else\n    a ? 3 : 4\n  end\nend\n",
            "folded_unless_dead_then" => "def fx(a)\n  unless true\n    a ? :x : :y\n  else\n    :b\n  end\nend\n",
            "folded_if_line" => "def fx(a)\n  if __LINE__\n    :a\n  end\nend\n",
            "folded_if_encoding" => "def fx(a)\n  if __ENCODING__\n    :a\n  end\nend\n",
            "folded_if_lambda" => "def fx(a)\n  if -> { a }\n    :a\n  end\nend\n",
            "unfolded_if_file" => "def fx(a)\n  if __FILE__\n    :a\n  end\nend\n",
            "unfolded_lambda_call" => "def fx(a)\n  if lambda { a }\n    :a\n  end\nend\n",
            "folded_paren_int" => "def fx(a)\n  if (1)\n    :a\n  end\nend\n",
            "unfolded_paren_nil" => "def fx(a)\n  if (nil)\n    :a\n  end\nend\n",
            "unfolded_paren_string" => "def fx(a)\n  if (\"x\")\n    :a\n  end\nend\n",
            "unfolded_paren_lambda" => "def fx(a)\n  if (-> { a ? 1 : 2 })\n    :a\n  end\nend\n",
            "folded_seq_int" => "def fx(a)\n  if (1; 2)\n    :a\n  else\n    :b\n  end\nend\n",
            "folded_seq_three" => "def fx(a)\n  if (:s; \"t\"; 2)\n    :a\n  end\nend\n",
            "folded_seq_nested" => "def fx(a)\n  if ((1; 2))\n    :a\n  end\nend\n",
            "unfolded_seq_call" => "def fx(a)\n  if (foo; 2)\n    :a\n  end\nend\n",
            "unfolded_seq_asgn" => "def fx(a)\n  if (x = 5; 2)\n    :a\n  end\nend\n",
            "unfolded_seq_last_lvar" => "def fx(a)\n  if (1; a)\n    :a\n  end\nend\n",
            "seq_opaque_nil_last" => "def fx(a)\n  if (1; nil)\n    :a\n  else\n    :b\n  end\nend\n",
            "seq_ivar_read" => "def fx(a)\n  if (@x; 2)\n    :a\n  end\nend\n",
            "seq_static_array" => "def fx(a)\n  if ([1]; 2)\n    :a\n  end\nend\n",
            "seq_dynamic_array" => "def fx(a)\n  if ([a]; 2)\n    :a\n  end\nend\n",
            "seq_static_hash" => "def fx(a)\n  if ({a: 1}; 2)\n    :a\n  end\nend\n",
            "seq_dynamic_hash" => "def fx(a)\n  if ({a: foo}; 2)\n    :a\n  end\nend\n",
            "seq_static_range" => "def fx(a)\n  if ((3..4); 2)\n    :a\n  end\nend\n",
            "seq_self" => "def fx(a)\n  if (self; 2)\n    :a\n  end\nend\n",
            "seq_array_self" => "def fx(a)\n  if ([self]; 2)\n    :a\n  end\nend\n",
            "seq_call_array" => "def fx(a)\n  if ([foo]; 2)\n    :a\n  end\nend\n",
            "seq_empty_paren" => "def fx(a)\n  if ()\n    :a\n  end\nend\n",
            "do_while" => "def fx(a)\n  begin\n    a\n  end while a\nend\n",
            "do_until" => "def fx(a)\n  begin\n    a\n  end until a\nend\n",
            "do_while_multi" => "def fx(a)\n  begin\n    a\n    b\n  end while a\nend\n",
            "oneline_match_required" => "def fx(a)\n  a => Integer\nend\n",
            "oneline_match_predicate" => "def fx(a)\n  a in Integer\nend\n",
            "oneline_match_void" => "def fx(a)\n  a => Integer\n  b\nend\n",
            "empty_then_void" => "def fx(a)\n  if a\n  end\n  b\nend\n",
            "empty_then_else_void" => "def fx(a)\n  if a\n  else\n    :b\n  end\n  b\nend\n",
            "empty_else_void" => "def fx(a)\n  if a\n    :a\n  else\n  end\n  b\nend\n",
            "empty_unless_then_void" => "def fx(a)\n  unless a\n  end\n  b\nend\n",
            "empty_when_void" => "def fx(a)\n  case a\n  when 1\n  end\n  b\nend\n",
            "empty_when_mixed" => "def fx(a)\n  case a\n  when 1\n  when 2 then :b\n  when 3\n  end\nend\n",
            "empty_case_else_void" => "def fx(a)\n  case a\n  when 1 then :a\n  else\n  end\n  b\nend\n",
            "empty_if_in_when" => "def fx(a)\n  case a\n  when 1\n    if b\n    end\n  end\nend\n",
            "empty_if_in_in_arm" => "def fx(a)\n  case a\n  in Integer\n    if b\n    end\n  end\nend\n",
            "empty_if_in_block" => "def fx(a)\n  foo do\n    if b\n    end\n  end\nend\n",
            "empty_if_rhs" => "def fx(a)\n  x = if b\n  end\nend\n"
          }.freeze
        end

        it "synthesizes tuples identical to Ruby's Coverage for every construct" do
          skip "branch coverage unsupported on this Ruby" unless SimpleCov.branch_coverage_supported?

          runtime = CoverageDifferential.runtime_branches(branch_fixtures)
          aggregate_failures do
            branch_fixtures.each do |name, source|
              synthesized = described_class.call(source)["branches"]
              expect(CoverageDifferential.strip_ids(synthesized))
                .to eq(CoverageDifferential.strip_ids(runtime.fetch(name))), "construct: #{name}"
            end
          end
        end
      end

      describe "method enumeration" do
        it "tracks top-level methods under \"Object\"" do
          result = described_class.call("def free; end\n")
          key = result["methods"].keys.first
          expect(key[0]).to eq("Object")
          expect(key[1]).to eq(:free)
        end

        it "enumerates a method as uncalled rather than unmeasured" do
          result = described_class.call("def free; end\n")
          expect(result["methods"].values).to eq([0])
        end

        it "tracks instance methods under their class name (as a string)" do
          result = described_class.call("class Foo\n  def bar; end\nend\n")
          key = result["methods"].keys.first
          expect(key[0]).to eq("Foo")
          expect(key[1]).to eq(:bar)
        end

        it "tracks methods inside modules" do
          result = described_class.call("module Foo\n  def bar; end\nend\n")
          key = result["methods"].keys.first
          expect(key[0]).to eq("Foo")
        end

        it "tracks namespaced classes by the source-form constant path" do
          result = described_class.call("class Foo::Bar\n  def baz; end\nend\n")
          key = result["methods"].keys.first
          expect(key[0]).to eq("Foo::Bar")
        end

        it "tracks `def self.method` the same as `def method`" do
          result = described_class.call("class Foo\n  def self.bar; end\nend\n")
          method_names = result["methods"].keys.map { |k| k[1] }
          expect(method_names).to include(:bar)
        end

        it "registers no method for a def in a folded dead arm" do
          result = described_class.call("if false\n  def dead(x)\n    x ? 1 : 2\n  end\nend\n")
          expect(result["methods"]).to be_empty
        end
      end

      describe "sequential id assignment" do
        it "assigns ascending ids across all branches and arms in source order" do
          src = "if a\n  :a\nelse\n  :b\nend\nif b\n  :c\nelse\n  :d\nend\n"
          result = described_class.call(src)
          ids = result["branches"].flat_map { |cond, arms| [cond[1]] + arms.keys.map { |a| a[1] } }
          expect(ids.length).to eq(6)
          expect(ids).to eq(ids.sort)
          expect(ids.uniq).to eq(ids)
        end
      end
    end
  end

  describe ".real_source_positions" do
    context "when Prism is not available" do
      before { allow(described_class).to receive(:available?).and_return(false) }

      it "returns nil so the eval_generated filter is a no-op" do
        expect(described_class.real_source_positions("def f; end\n")).to be_nil
      end
    end

    context "when Prism is available", if: described_class.available? do
      it "returns nil on a parse failure" do
        expect(described_class.real_source_positions("def f(\n")).to be_nil
      end

      it "lists branch condition start lines" do
        src = "x = 1\nif x > 0\n  :a\nend\ncase x\nwhen 1 then :b\nend\n"
        positions = described_class.real_source_positions(src)
        expect(positions[:branches]).to contain_exactly(2, 5)
      end

      it "names methods by the class that lexically encloses them" do
        source = "class A\n  class B\n    def inner; end\n  end\n  def outer; end\nend\n"

        expect(described_class.call(source)["methods"].keys)
          .to eq([["B", :inner, 3, 4, 3, 18], ["A", :outer, 5, 2, 5, 16]])
      end

      it "names a method outside any class Object, the way Coverage does" do
        expect(described_class.call("def bare; end\n")["methods"].keys)
          .to eq([["Object", :bare, 1, 0, 1, 13]])
      end

      it "names methods inside a module by that module" do
        expect(described_class.call("module M\n  def m; end\nend\n")["methods"].keys)
          .to eq([["M", :m, 2, 2, 2, 12]])
      end

      it "lists method (name, start_line) pairs" do
        src = "class Foo\n  def bar; end\n  def baz; end\nend\n"
        positions = described_class.real_source_positions(src)
        expect(positions[:methods]).to contain_exactly([:bar, 2], [:baz, 3])
      end

      it "returns empty sets for a source with no defs or branches" do
        positions = described_class.real_source_positions("a = 1\nb = a + 1\n")
        expect(positions[:branches]).to be_empty
        expect(positions[:methods]).to be_empty
      end
    end
  end

  describe "naming the class a method belongs to", if: described_class.available? do
    let(:visitor) { SimpleCov::StaticCoverageExtractor::Visitor.new }

    it "names a constant path by its source form" do
      path = Prism.parse("class Foo::Bar; end\n").value.statements.body.first.constant_path

      expect(visitor.send(:constant_name, path)).to eq("Foo::Bar")
    end

    it "names a class that has no constant path at all" do
      expect(visitor.send(:constant_name, nil)).to eq("<anonymous>")
    end

    it "names anything else by itself" do
      expect(visitor.send(:constant_name, Comparable)).to eq("Comparable")
    end
  end

  describe "a def whose methods are suppressed", if: described_class.available? do
    let(:visitor) { SimpleCov::StaticCoverageExtractor::Visitor.new }

    before { visitor.instance_variable_set(:@suppress_methods, true) }

    it "registers no method and still collects the branches inside it" do
      visitor.visit(Prism.parse("def f\n  if a\n    1\n  end\nend\n").value)

      expect(visitor.methods).to be_empty
      expect(visitor.branches.keys.map(&:first)).to eq([:if])
    end
  end

  describe "the modern branch conventions", if: described_class.available? do
    before { stub_const("#{described_class}::LocationConventions::LEGACY_COVERAGE_LOCATIONS", false) }

    def modern_branches(source)
      described_class.call(source)["branches"].to_h do |condition, arms|
        [CoverageDifferential.tuple_identity(condition),
          arms.keys.map { |arm| CoverageDifferential.tuple_identity(arm) }.sort_by(&:to_s)]
      end
    end

    {
      "an empty explicit else, spanning else through end" =>
        ["def fx(a)\n  if a\n    :a\n  else\n  end\nend\n",
          {["if", 2, 2, 5, 5] => [["else", 4, 2, 5, 5], ["then", 3, 4, 3, 6]]}],
      "an empty when arm, keeping the clause's own range" =>
        ["def fx(a)\n  case a\n  when 1\n  end\nend\n",
          {["case", 2, 2, 4, 5] => [["else", 2, 2, 4, 5], ["when", 3, 2, 3, 8]]}],
      "an empty case else, spanning else through end" =>
        ["def fx(a)\n  case a\n  when 1 then :a\n  else\n  end\nend\n",
          {["case", 2, 2, 5, 5] => [["else", 4, 2, 5, 5], ["when", 3, 14, 3, 16]]}],
      "an empty loop body, falling back to the loop's range" =>
        ["def fx(a)\n  while a\n  end\nend\n",
          {["while", 2, 2, 3, 5] => [["body", 2, 2, 3, 5]]}],
      "an empty then, collapsing to the predicate's end" =>
        ["def fx(a)\n  if a\n  end\nend\n",
          {["if", 2, 2, 3, 5] => [["else", 2, 2, 3, 5], ["then", 2, 6, 2, 6]]}],
      "an empty unless then, keeping the node's range" =>
        ["def fx(a)\n  unless a\n  end\nend\n",
          {["unless", 2, 2, 3, 5] => [["else", 2, 2, 3, 5], ["then", 2, 2, 3, 5]]}],
      "an empty unless else, spanning the construct rather than the else clause" =>
        ["def fx(a)\n  unless a\n    :a\n  else\n  end\nend\n",
          {["unless", 2, 2, 5, 5] => [["else", 2, 2, 5, 5], ["then", 3, 4, 3, 6]]}],
      "an elsif chain, whose nested condition ends at the shared end" =>
        ["def fx(a)\n  if a == 1\n    :a\n  elsif a == 2\n    :b\n  end\nend\n",
          {["if", 2, 2, 6, 5] => [["else", 4, 2, 6, 5], ["then", 3, 4, 3, 6]],
           ["if", 4, 2, 6, 5] => [["else", 4, 2, 6, 5], ["then", 5, 4, 5, 6]]}],
      "an empty when arm with another after it, still keeping its own range" =>
        ["def fx(a)\n  case a\n  when 1\n  when 2 then :b\n  end\nend\n",
          {["case", 2, 2, 5, 5] =>
            [["else", 2, 2, 5, 5], ["when", 3, 2, 3, 8], ["when", 4, 14, 4, 16]]}],
      "a do-while body, spanning the whole begin block rather than its statements" =>
        ["def fx(a)\n  begin\n    a\n  end while a\nend\n",
          {["while", 2, 2, 4, 13] => [["body", 2, 2, 4, 5]]}]
    }.each do |description, (source, expected)|
      it "places #{description}" do
        expect(modern_branches(source)).to eq(expected)
      end
    end

    it "emits no branch for a one-line pattern match" do
      expect(described_class.call("a => Integer\n")["branches"]).to be_empty
      expect(described_class.call("a in Integer\n")["branches"]).to be_empty
    end
  end

  describe "the legacy branch conventions", if: described_class.available? do
    before { stub_const("#{described_class}::LocationConventions::LEGACY_COVERAGE_LOCATIONS", true) }

    def legacy_branches(source)
      described_class.call(source)["branches"].to_h do |condition, arms|
        [CoverageDifferential.tuple_identity(condition),
          arms.keys.map { |arm| CoverageDifferential.tuple_identity(arm) }.sort_by(&:to_s)]
      end
    end

    {
      "an elsif chain, whose nested condition spans to the outer end" =>
        ["def fx(a)\n  if a == 1\n    :a\n  elsif a == 2\n    :b\n  end\nend\n",
          {["if", 2, 2, 6, 5] => [["else", 4, 2, 5, 6], ["then", 3, 4, 3, 6]],
           ["if", 4, 2, 5, 6] => [["else", 4, 2, 5, 6], ["then", 5, 4, 5, 6]]}],

      "an empty else whose result is discarded, collapsed to a point" =>
        ["def fx(a)\n  if a\n    :a\n  else\n  end\n  :tail\nend\n",
          {["if", 2, 2, 5, 5] => [["else", 4, 6, 4, 6], ["then", 3, 4, 3, 6]]}],

      "an empty else whose result is returned, spanning the construct" =>
        ["def fx(a)\n  if a\n    :a\n  else\n  end\nend\n",
          {["if", 2, 2, 5, 5] => [["else", 2, 2, 5, 5], ["then", 3, 4, 3, 6]]}],

      "a when with an empty body, spanning to the following arm" =>
        ["def fx(a)\n  case a\n  when 1\n  when 2 then :b\n  end\nend\n",
          {["case", 2, 2, 5, 5] =>
            [["else", 2, 2, 5, 5], ["when", 3, 2, 4, 16], ["when", 4, 14, 4, 16]]}],

      "a trailing when with an empty body, spanning to the case tail" =>
        ["def fx(a)\n  case a\n  when 1 then :a\n  when 2\n  end\nend\n",
          {["case", 2, 2, 5, 5] =>
            [["else", 2, 2, 5, 5], ["when", 3, 14, 3, 16], ["when", 4, 2, 4, 8]]}],

      "a trailing when with an empty body after then, spanning its conditions" =>
        ["def fx(a)\n  case a\n  when 1 then :a\n  when 2 then\n  end\nend\n",
          {["case", 2, 2, 5, 5] =>
            [["else", 2, 2, 5, 5], ["when", 3, 14, 3, 16], ["when", 4, 2, 4, 8]]}],

      "an in clause with an empty body after then, collapsed to its pattern's end" =>
        ["def fx(a)\n  case a\n  in Integer then\n  end\nend\n",
          {["case", 2, 2, 4, 5] => [["else", 2, 2, 4, 5], ["in", 3, 12, 3, 12]]}],

      "a loop body" =>
        ["def fx(a)\n  while a\n    :body\n  end\nend\n",
          {["while", 2, 2, 4, 5] => [["body", 3, 4, 3, 9]]}],

      "an empty loop body, collapsed to a point past the predicate" =>
        ["def fx(a)\n  until a\n  end\nend\n",
          {["until", 2, 2, 3, 5] => [["body", 2, 9, 2, 9]]}],

      "a do-while body, which is written before its predicate" =>
        ["def fx(a)\n  begin\n    :body\n  end while a\nend\n",
          {["while", 2, 2, 4, 13] => [["body", 3, 4, 3, 9]]}],

      "a rightward pattern match, whose else spans the whole match" =>
        ["def fx(a)\n  a => Integer\nend\n",
          {["case", 2, 2, 2, 14] => [["else", 2, 2, 2, 14], ["in", 2, 7, 2, 14]]}],

      "a boolean pattern match, whose else spans the pattern" =>
        ["def fx(a)\n  a in Integer\nend\n",
          {["case", 2, 2, 2, 14] => [["else", 2, 7, 2, 14], ["in", 2, 7, 2, 14]]}],

      "a three-deep elsif chain ending in an else" =>
        ["def fx(a)\n  if a == 1\n    :a\n  elsif a == 2\n    :b\n  elsif a == 3\n    " \
         ":c\n  else\n    :d\n  end\nend\n",
          {["if", 2, 2, 10, 5] => [["else", 4, 2, 9, 6], ["then", 3, 4, 3, 6]],
           ["if", 4, 2, 9, 6] => [["else", 6, 2, 9, 6], ["then", 5, 4, 5, 6]],
           ["if", 6, 2, 9, 6] => [["else", 9, 4, 9, 6], ["then", 7, 4, 7, 6]]}],

      "a three-deep elsif chain with no else at all" =>
        ["def fx(a)\n  if a == 1\n    :a\n  elsif a == 2\n    :b\n  elsif a == 3\n    :c\n  end\nend\n",
          {["if", 2, 2, 8, 5] => [["else", 4, 2, 7, 6], ["then", 3, 4, 3, 6]],
           ["if", 4, 2, 7, 6] => [["else", 6, 2, 7, 6], ["then", 5, 4, 5, 6]],
           ["if", 6, 2, 7, 6] => [["else", 6, 2, 7, 6], ["then", 7, 4, 7, 6]]}],

      "an elsif with an empty body whose result is returned" =>
        ["def fx(a)\n  if a == 1\n    :a\n  elsif a == 2\n  end\nend\n",
          {["if", 2, 2, 5, 5] => [["else", 4, 2, 4, 14], ["then", 3, 4, 3, 6]],
           ["if", 4, 2, 4, 14] => [["else", 4, 2, 4, 14], ["then", 4, 2, 4, 14]]}],

      "an elsif with an empty body whose result is discarded" =>
        ["def fx(a)\n  if a == 1\n    :a\n  elsif a == 2\n  end\n  :tail\nend\n",
          {["if", 2, 2, 5, 5] => [["else", 4, 2, 4, 14], ["then", 3, 4, 3, 6]],
           ["if", 4, 2, 4, 14] => [["else", 4, 2, 4, 14], ["then", 4, 14, 4, 14]]}],

      "an empty first when followed by an else" =>
        ["def fx(a)\n  case a\n  when 1\n  when 2 then :b\n  else :c\n  end\nend\n",
          {["case", 2, 2, 6, 5] =>
            [["else", 5, 7, 5, 9], ["when", 3, 2, 5, 9], ["when", 4, 14, 4, 16]]}],

      "an empty trailing when followed by an else" =>
        ["def fx(a)\n  case a\n  when 1 then :a\n  when 2\n  else :c\n  end\nend\n",
          {["case", 2, 2, 6, 5] =>
            [["else", 5, 7, 5, 9], ["when", 3, 14, 3, 16], ["when", 4, 2, 5, 9]]}],

      "a case with an else, whose arms keep their own bodies" =>
        ["def fx(a)\n  case a\n  when 1 then :a\n  when 2 then :b\n  else\n    :c\n  end\nend\n",
          {["case", 2, 2, 7, 5] =>
            [["else", 6, 4, 6, 6], ["when", 3, 14, 3, 16], ["when", 4, 14, 4, 16]]}],

      "a case whose result is discarded, collapsing its empty arm" =>
        ["def fx(a)\n  case a\n  when 1\n  end\n  :tail\nend\n",
          {["case", 2, 2, 4, 5] => [["else", 2, 2, 4, 5], ["when", 3, 8, 3, 8]]}],

      "an empty in arm, which collapses even in value position" =>
        ["def fx(a)\n  case a\n  in Integer\n  in String then :s\n  end\nend\n",
          {["case", 2, 2, 5, 5] =>
            [["else", 2, 2, 5, 5], ["in", 3, 12, 3, 12], ["in", 4, 17, 4, 19]]}],

      "an empty trailing in arm" =>
        ["def fx(a)\n  case a\n  in Integer then :i\n  in String\n  end\nend\n",
          {["case", 2, 2, 5, 5] =>
            [["else", 2, 2, 5, 5], ["in", 3, 18, 3, 20], ["in", 4, 11, 4, 11]]}],

      "a case/in with an else of its own" =>
        ["def fx(a)\n  case a\n  in Integer then :i\n  else :o\n  end\nend\n",
          {["case", 2, 2, 5, 5] => [["else", 4, 7, 4, 9], ["in", 3, 18, 3, 20]]}],

      "a do-until, which reads its predicate after the body too" =>
        ["def fx(a)\n  begin\n    :body\n  end until a\nend\n",
          {["until", 2, 2, 4, 13] => [["body", 3, 4, 3, 9]]}],

      "a do-while with an empty body, collapsed to a point" =>
        ["def fx(a)\n  begin\n  end while a\nend\n",
          {["while", 2, 2, 3, 13] => [["body", 2, 7, 2, 7]]}],

      "an if with no else, whose result is returned" =>
        ["def fx(a)\n  if a\n    :a\n  end\nend\n",
          {["if", 2, 2, 4, 5] => [["else", 2, 2, 4, 5], ["then", 3, 4, 3, 6]]}],

      "an if with no else, whose result is discarded" =>
        ["def fx(a)\n  if a\n    :a\n  end\n  :tail\nend\n",
          {["if", 2, 2, 4, 5] => [["else", 2, 2, 4, 5], ["then", 3, 4, 3, 6]]}],

      "an unless with no else, whose result is discarded" =>
        ["def fx(a)\n  unless a\n    :a\n  end\n  :tail\nend\n",
          {["unless", 2, 2, 4, 5] => [["else", 2, 2, 4, 5], ["then", 3, 4, 3, 6]]}],

      "an unless with an empty else, whose result is returned" =>
        ["def fx(a)\n  unless a\n    :a\n  else\n  end\nend\n",
          {["unless", 2, 2, 5, 5] => [["else", 2, 2, 5, 5], ["then", 3, 4, 3, 6]]}],

      "a chain whose last elsif has an empty body" =>
        ["def fx(a)\n  if a == 1\n    :a\n  elsif a == 2\n    :b\n  elsif a == 3\n  end\nend\n",
          {["if", 2, 2, 7, 5] => [["else", 4, 2, 6, 14], ["then", 3, 4, 3, 6]],
           ["if", 4, 2, 6, 14] => [["else", 6, 2, 6, 14], ["then", 5, 4, 5, 6]],
           ["if", 6, 2, 6, 14] => [["else", 6, 2, 6, 14], ["then", 6, 2, 6, 14]]}],

      "a chain ending in an empty else" =>
        ["def fx(a)\n  if a == 1\n    :a\n  elsif a == 2\n    :b\n  else\n  end\nend\n",
          {["if", 2, 2, 7, 5] => [["else", 4, 2, 6, 6], ["then", 3, 4, 3, 6]],
           ["if", 4, 2, 6, 6] => [["else", 4, 2, 6, 6], ["then", 5, 4, 5, 6]]}],

      "an empty when between two others, with an else after them" =>
        ["def fx(a)\n  case a\n  when 1 then :a\n  when 2\n  when 3 then :c\n  else :d\n  end\nend\n",
          {["case", 2, 2, 7, 5] =>
            [["else", 6, 7, 6, 9], ["when", 3, 14, 3, 16], ["when", 4, 2, 6, 9], ["when", 5, 14, 5, 16]]}],

      "an empty when and an empty else, whose result is returned" =>
        ["def fx(a)\n  case a\n  when 1\n  else\n  end\nend\n",
          {["case", 2, 2, 5, 5] => [["else", 2, 2, 5, 5], ["when", 3, 2, 3, 8]]}],

      "an empty when and an empty else, whose result is discarded" =>
        ["def fx(a)\n  case a\n  when 1\n  else\n  end\n  :tail\nend\n",
          {["case", 2, 2, 5, 5] => [["else", 4, 6, 4, 6], ["when", 3, 8, 3, 8]]}],

      "an empty third when with no else after it" =>
        ["def fx(a)\n  case a\n  when 1 then :a\n  when 2 then :b\n  when 3\n  end\nend\n",
          {["case", 2, 2, 6, 5] =>
            [["else", 2, 2, 6, 5], ["when", 3, 14, 3, 16], ["when", 4, 14, 4, 16], ["when", 5, 2, 5, 8]]}],

      "an empty third when whose case result is discarded" =>
        ["def fx(a)\n  case a\n  when 1 then :a\n  when 2 then :b\n  when 3\n  end\n  :tail\nend\n",
          {["case", 2, 2, 6, 5] =>
            [["else", 2, 2, 6, 5], ["when", 3, 14, 3, 16], ["when", 4, 14, 4, 16], ["when", 5, 8, 5, 8]]}],

      "an empty third in arm with no else after it" =>
        ["def fx(a)\n  case a\n  in 1 then :a\n  in 2 then :b\n  in 3\n  end\nend\n",
          {["case", 2, 2, 6, 5] =>
            [["else", 2, 2, 6, 5], ["in", 3, 12, 3, 14], ["in", 4, 12, 4, 14], ["in", 5, 6, 5, 6]]}],

      "a ternary" =>
        ["def fx(a)\n  a ? :t : :f\nend\n",
          {["if", 2, 2, 2, 13] => [["else", 2, 11, 2, 13], ["then", 2, 6, 2, 8]]}],

      "a modifier if" =>
        ["def fx(a)\n  :t if a\nend\n",
          {["if", 2, 2, 2, 9] => [["else", 2, 2, 2, 9], ["then", 2, 2, 2, 4]]}],

      "a modifier unless" =>
        ["def fx(a)\n  :t unless a\nend\n",
          {["unless", 2, 2, 2, 13] => [["else", 2, 2, 2, 13], ["then", 2, 2, 2, 4]]}],

      "a modifier if whose result is discarded" =>
        ["def fx(a)\n  :t if a\n  :tail\nend\n",
          {["if", 2, 2, 2, 9] => [["else", 2, 2, 2, 9], ["then", 2, 2, 2, 4]]}],

      "safe navigation, bare and with arguments and a block" =>
        ["def fx(a)\n  a&.to_s\nend\n",
          {["&.", 2, 2, 2, 9] => [["else", 2, 2, 2, 9], ["then", 2, 2, 2, 9]]}],

      "an empty trailing when matching two values" =>
        ["def fx(a)\n  case a\n  when 1 then :a\n  when 2, 3\n  end\nend\n",
          {["case", 2, 2, 5, 5] =>
            [["else", 2, 2, 5, 5], ["when", 3, 14, 3, 16], ["when", 4, 2, 4, 11]]}],

      "an empty trailing when matching two values, result discarded" =>
        ["def fx(a)\n  case a\n  when 1 then :a\n  when 2, 3\n  end\n  :tail\nend\n",
          {["case", 2, 2, 5, 5] =>
            [["else", 2, 2, 5, 5], ["when", 3, 14, 3, 16], ["when", 4, 11, 4, 11]]}],

      "an empty when matching two values, with an arm after it" =>
        ["def fx(a)\n  case a\n  when 1, 2\n  when 3 then :c\n  end\nend\n",
          {["case", 2, 2, 5, 5] =>
            [["else", 2, 2, 5, 5], ["when", 3, 2, 4, 16], ["when", 4, 14, 4, 16]]}],

      "an empty trailing in arm matching alternatives" =>
        ["def fx(a)\n  case a\n  in 1 then :a\n  in 2 | 3\n  end\nend\n",
          {["case", 2, 2, 5, 5] =>
            [["else", 2, 2, 5, 5], ["in", 3, 12, 3, 14], ["in", 4, 10, 4, 10]]}]
    }.each do |description, (source, expected)|
      it "places #{description}" do
        expect(legacy_branches(source)).to eq(expected)
      end
    end

    it "numbers and zeroes every tuple of a rightward pattern match" do
      expect(described_class.call("a => Integer\n")["branches"])
        .to eq([:case, 0, 1, 0, 1, 12] => {[:in, 1, 1, 5, 1, 12] => 0, [:else, 2, 1, 0, 1, 12] => 0})
    end

    it "numbers and zeroes every tuple of a boolean pattern match" do
      expect(described_class.call("a in Integer\n")["branches"])
        .to eq([:case, 0, 1, 0, 1, 12] => {[:in, 1, 1, 5, 1, 12] => 0, [:else, 2, 1, 5, 1, 12] => 0})
    end

    it "descends into the expression a one-line pattern matches" do
      expect(described_class.call("(a ? 1 : 2) => Integer\n")["branches"].keys.map(&:first)).to eq(%i[case if])
      expect(described_class.call("(a ? 1 : 2) in Integer\n")["branches"].keys.map(&:first)).to eq(%i[case if])
    end

    it "renders a constant path, and names an absent one" do
      collector = Object.new.extend(described_class::MethodCollector)

      expect(collector.send(:constant_name, nil)).to eq("<anonymous>")
      expect(collector.send(:constant_name, Struct.new(:slice).new("Foo::Bar"))).to eq("Foo::Bar")
      expect(collector.send(:constant_name, Object.new)).to match(/\A#<Object/)
    end

    it "treats every node as being in value position without a map" do
      context = Object.new.extend(described_class::LocationConventions)

      expect(context.send(:value_position?, :any_node_at_all)).to be true
    end

    it "consults the map where the visitor built one" do
      context = Object.new.extend(described_class::LocationConventions)
      marked = {}.compare_by_identity
      node = Object.new
      marked[node] = true
      context.instance_variable_set(:@value_positions, marked)

      expect(context.send(:value_position?, node)).to be true
      expect(context.send(:value_position?, Object.new)).to be false
    end
  end

  describe SimpleCov::StaticCoverageExtractor::ValuePositions,
    if: SimpleCov::StaticCoverageExtractor.available? do
    def marked_leaves(source)
      require "prism"
      root = Prism.parse(source).value
      described_class.call(root).keys.filter_map do |node|
        node.slice if node.is_a?(Prism::SymbolNode) || node.is_a?(Prism::IntegerNode)
      end.sort
    end

    it "marks a method's last statement and not the ones before it" do
      expect(marked_leaves("def fx\n  :first\n  :last\nend\n")).to eq([":last"])
    end

    it "marks a nested method's tail even inside a discarded position" do
      expect(marked_leaves("x = def fx\n  :tail\nend\n")).to eq([":tail"])
    end

    it "forwards tail position into both arms of an if and an unless" do
      expect(marked_leaves("def fx(a)\n  if a\n    :then\n  else\n    :else\n  end\nend\n"))
        .to eq([":else", ":then"])
      expect(marked_leaves("def fx(a)\n  unless a\n    :then\n  else\n    :else\n  end\nend\n"))
        .to eq([":else", ":then"])
    end

    it "forwards tail position through an elsif chain" do
      source = "def fx(a)\n  if a\n    :a\n  elsif a\n    :b\n  else\n    :c\n  end\nend\n"
      expect(marked_leaves(source)).to eq([":a", ":b", ":c"])
    end

    it "forwards tail position into a case's when arms and its else" do
      source = "def fx(a)\n  case a\n  when 1 then :a\n  when 2 then :b\n  else :c\n  end\nend\n"
      expect(marked_leaves(source)).to eq([":a", ":b", ":c"])
    end

    it "forwards tail position through a begin block" do
      expect(marked_leaves("def fx\n  begin\n    :inner\n  end\nend\n")).to eq([":inner"])
    end

    it "discards tail position into a case/in arm" do
      source = "def fx(a)\n  case a\n  in Integer then :i\n  else :o\n  end\nend\n"
      expect(marked_leaves(source)).to be_empty
    end

    it "discards tail position into a loop body, a block, and an assignment" do
      expect(marked_leaves("def fx(a)\n  while a\n    :body\n  end\nend\n")).to be_empty
      expect(marked_leaves("def fx(a)\n  a.each { :body }\nend\n")).to be_empty
      expect(marked_leaves("def fx\n  x = :assigned\nend\n")).to be_empty
    end

    it "discards tail position into an argument" do
      expect(marked_leaves("def fx\n  puts(:arg)\nend\n")).to be_empty
    end

    it "marks the program's own last statement" do
      expect(marked_leaves(":only\n")).to eq([":only"])
      expect(marked_leaves(":first\n:second\n")).to eq([":second"])
    end

    it "answers an identity set, so equal-looking nodes stay distinct" do
      require "prism"
      root = Prism.parse("def fx\n  :same\nend\n").value
      positions = described_class.call(root)

      expect(positions).to be_compare_by_identity
      expect(positions.values.uniq).to eq([true])
    end

    it "ignores anything that is not a node" do
      expect { described_class.mark(nil, true, {}) }.not_to raise_error
      expect(described_class.mark("not a node", true, {})).to be_nil
    end
  end
end
