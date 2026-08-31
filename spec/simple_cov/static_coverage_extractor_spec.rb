# frozen_string_literal: true

require "helper"
require "coverage"
require "support/coverage_differential"

RSpec.describe SimpleCov::StaticCoverageExtractor do
  describe ".call" do
    context "with parseable and unparseable sources" do
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
    end
  end

  describe "branch enumeration" do
    def static_branches(source)
      described_class.call(source)["branches"]
    end

    def branch_shape(source)
      static_branches(source).to_h { |condition, arms| [condition.first, arms.keys.map(&:first)] }
    end

    def condition_kinds(source)
      static_branches(source).keys.map(&:first)
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

    it "matches Coverage for `if`/`else` block form" do
      src = "x = 1\nif x > 0\n  :a\nelse\n  :b\nend\n"

      expect(branch_shape(src)).to match(if: contain_exactly(:then, :else))
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

      expect(branch_shape(src)).to eq(until: [:body])
    end

    it "matches Coverage for `unless` block form" do
      src = "x = 1\nunless x > 0\n  :a\nelse\n  :b\nend\n"

      expect(branch_shape(src)).to match(unless: contain_exactly(:then, :else))
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

      expect(branch_shape(src)).to match("&.": contain_exactly(:then, :else))
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
      let(:paren_trio) { ["if (nil)\n  x\nend\n", "if (\"x\")\n  a\nend\n", "if (-> { x })\n  a\nend\n"] }
      let(:eliminable_sequences) do
        ["if (1; 2)\n  x\nelse\n  y\nend\n", "if (:s; \"t\"; 2)\n  x\nend\n", "if ((1; 2))\n  x\nend\n"]
      end
      let(:uneliminable_sequences) do
        ["if (a; 2)\n  x\nend\n", "if (x = 5; 2)\n  x\nend\n",
          "if ([a]; 2)\n  x\nend\n", "if ({a: b}; 2)\n  x\nend\n"]
      end
      let(:eliminable_read_sequences) do
        ["if (@x; 2)\n  a\nend\n", "if ([1]; 2)\n  a\nend\n",
          "if ({a: 1}; 2)\n  a\nend\n", "if ((3..4); 2)\n  a\nend\n"]
      end

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

      it "keeps the branch for `__FILE__`, which the Prism compiler does not fold" do
        expect(condition_kinds("if __FILE__\n  x\nend\n")).to eq([:if])
      end

      it "still tracks a `lambda` call (only the `->` literal folds)" do
        expect(static_branches("if lambda { x }\n  a\nend\n").keys.first.first).to eq(:if)
      end

      it "keeps the branch for `(nil)`, `(\"x\")`, and `(-> {})`" do
        expect(paren_trio.map { |src| condition_kinds(src) }).to all(eq([:if]))
      end

      it "folds a multi-statement paren condition with eliminable leading statements" do
        expect(eliminable_sequences.map { |src| static_branches(src) }).to all(be_empty)
      end

      it "keeps the branch when a leading statement is not eliminable" do
        expect(uneliminable_sequences.map { |src| condition_kinds(src) }).to all(eq([:if]))
      end

      it "keeps the branch when the last statement of a sequence is not a foldable literal" do
        expect(static_branches("if (1; a)\n  x\nend\n").keys.first.first).to eq(:if)
      end

      it "keeps the branch for an empty paren condition" do
        expect(static_branches("if ()\n  x\nend\n").keys.first.first).to eq(:if)
      end

      it "applies paren opacity to the last statement of a sequence" do
        expect(condition_kinds("if (1; nil)\n  x\nelse\n  y\nend\n")).to eq([:if])
      end

      it "folds eliminable leading reads and static containers" do
        expect(eliminable_read_sequences.map { |src| static_branches(src) }).to all(be_empty)
      end

      it "emits nothing for a branch nested in a dead then arm" do
        expect(static_branches("if false\n  if a\n    :x\n  end\nend\n")).to be_empty
      end

      it "emits nothing for a branch nested in a dead else arm" do
        expect(static_branches("if true\n  :a\nelse\n  if a\n    :x\n  end\nend\n")).to be_empty
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
        expect(condition_kinds("unless true\n  a ? :x : :y\nelse\n  if b\n    :z\n  end\nend\n")).to eq([:if])
      end

      it "keeps the body contents of a folded falsy unless" do
        expect(condition_kinds("unless false\n  if b\n    :z\n  end\nelse\n  a ? :x : :y\nend\n")).to eq([:if])
      end
    end
  end

  describe "container eliminability predicates" do
    def predicate(name, source)
      node = Prism.parse(source).value.statements.body.first
      SimpleCov::StaticCoverageExtractor::Visitor.new.send(name, node)
    end

    def predicates(name, sources)
      sources.map { |source| predicate(name, source) }
    end

    it "treats containers of scalar literals as static" do
      expect(predicates(:static_container?, ["[1, 2]", "{a: 1}", "3..4", "..4"])).to all(be true)
    end

    it "rejects containers with effectful or non-literal contents" do
      sources = ["[foo]", "{a: foo}", "{**foo}", "foo..4", "foo"]

      expect(predicates(:static_container?, sources)).to all(be false)
    end

    it "rejects a container that is only partly literal" do
      sources = ["[1, foo]", "[foo, 1]", "{a: 1, b: foo}"]

      expect(predicates(:static_container?, sources)).to all(be false)
    end

    it "reads both sides of a hash pair and of a range" do
      sources = ["{foo => 1}", "{1 => foo}", "1..foo"]

      expect(predicates(:static_container?, sources)).to all(be false)
    end

    it "reads an endless range as static" do
      expect(predicate(:static_container?, "1..")).to be true
    end

    it "reads an empty container as static" do
      expect(predicates(:static_container?, ["[]", "{}"])).to all(be true)
    end

    it "answers about a node that is no container at all" do
      expect(predicate(:static_container?, ":sym")).to be false
    end

    describe "eliminable when discarded" do
      it "counts a literal and a read with nothing behind it" do
        expect(predicates(:eliminable_when_discarded?, ["1", "self"])).to all(be true)
      end

      it "counts out a call, which could do anything" do
        expect(predicate(:eliminable_when_discarded?, "foo(1)")).to be false
      end

      it "sees through parentheses, however many statements they hold" do
        sources = ["(1)", "(1; 2)", "((1))"]

        expect(predicates(:eliminable_when_discarded?, sources)).to all(be true)
      end

      it "counts out parentheses holding anything that is not" do
        sources = ["(1; foo(1))", "(foo(1); 1)"]

        expect(predicates(:eliminable_when_discarded?, sources)).to all(be false)
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
        expect(["(1)", "((1))"].map { |source| unwrapped(source) }).to all(eq("Prism::IntegerNode"))
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
        expect(predicates(:folded_condition, ["false", "nil"])).to all(eq(:falsy))
      end

      it "answers truthy for every other folding literal" do
        sources = ["true", "1", ":sym", "-> {}"]

        expect(predicates(:folded_condition, sources)).to all(eq(:truthy))
      end

      it "answers nothing for a condition that does not fold" do
        sources = ["foo", "!true", "/re/", "[]"]

        expect(predicates(:folded_condition, sources)).to all(be_nil)
      end

      it "sees through parentheses for a truthy literal they do not shield" do
        expect(predicate(:folded_condition, "(1)")).to eq(:truthy)
      end

      it "sees through parentheses for a falsy literal they do not shield" do
        expect(predicate(:folded_condition, "(false)")).to eq(:falsy)
      end

      it "declines to fold the literals parentheses shield" do
        expect(predicates(:folded_condition, ["(nil)", '("x")'])).to all(be_nil)
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

    def expect_every_fixture_to_match_runtime
      runtime = CoverageDifferential.runtime_branches(branch_fixtures)
      aggregate_failures do
        branch_fixtures.each do |name, source|
          synthesized = described_class.call(source)["branches"]
          expect(CoverageDifferential.strip_ids(synthesized))
            .to eq(CoverageDifferential.strip_ids(runtime.fetch(name))), "construct: #{name}"
        end
      end
    end

    it "synthesizes tuples identical to Ruby's Coverage for every construct" do
      skip "branch coverage unsupported on this Ruby" unless SimpleCov.branch_coverage_supported?

      expect_every_fixture_to_match_runtime
    end
  end

  describe "method enumeration" do
    it "tracks top-level methods under \"Object\"" do
      result = described_class.call("def free; end\n")

      expect(result["methods"].keys.first).to start_with("Object", :free)
    end

    it "enumerates a method as uncalled rather than unmeasured" do
      result = described_class.call("def free; end\n")
      expect(result["methods"].values).to eq([0])
    end

    it "tracks instance methods under their class name (as a string)" do
      result = described_class.call("class Foo\n  def bar; end\nend\n")

      expect(result["methods"].keys.first).to start_with("Foo", :bar)
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

      expect(ids).to eq([0, 1, 2, 3, 4, 5])
    end
  end

  describe ".real_source_positions" do
    context "with parseable and unparseable sources" do
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

        expect(positions).to match(branches: be_empty, methods: be_empty)
      end
    end
  end

  describe "naming the class a method belongs to" do
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

  describe "one-line pattern matching" do
    it "descends into the expression a rightward pattern matches" do
      expect(described_class.call("(a ? 1 : 2) => Integer\n")["branches"].keys.map(&:first)).to eq([:if])
    end

    it "descends into the expression a boolean pattern matches" do
      expect(described_class.call("(a ? 1 : 2) in Integer\n")["branches"].keys.map(&:first)).to eq([:if])
    end
  end

  describe "naming a constant path" do
    def constant_name_of(path)
      Object.new.extend(described_class::MethodCollector).send(:constant_name, path)
    end

    it "names an absent constant path" do
      expect(constant_name_of(nil)).to eq("<anonymous>")
    end

    it "renders a constant path by the source it slices" do
      expect(constant_name_of(Struct.new(:slice).new("Foo::Bar"))).to eq("Foo::Bar")
    end

    it "renders anything else by itself" do
      expect(constant_name_of(Object.new)).to match(/\A#<Object/)
    end
  end
end
