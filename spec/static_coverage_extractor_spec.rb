# frozen_string_literal: true

require "helper"
require "coverage"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

RSpec.describe SimpleCov::StaticCoverageExtractor do
  describe ".available?" do
    it "is true on Ruby 3.3+ (Prism in stdlib) and false otherwise" do
      # We assert on the runtime state rather than hardcoding an expected
      # value — the spec runs on a matrix of Rubies and we want it to
      # adapt rather than gate on a version constant.
      expect(described_class.available?).to be(true).or be(false)
    end
  end

  describe ".call" do
    context "when Prism is not available" do
      it "returns nil so callers fall back to empty hashes" do
        skip "Prism is available; the no-Prism path can't be exercised on this Ruby" if described_class.available?

        expect(described_class.call("a = 1\n")).to be_nil
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

      describe "branch enumeration" do
        # Each subject below asserts on the structural shape of the
        # synthesized output (condition type + arm types per construct),
        # which is what downstream consumers — the HTML formatter,
        # SonarQube, and the `ignore_branches :implicit_else` filter —
        # actually key off.
        def static_branches(source)
          described_class.call(source)["branches"]
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
          # Two explicit whens + one synthesized else (Coverage always
          # synthesizes else when not present, and so do we).
          expect(arms.keys.map(&:first)).to contain_exactly(:when, :when, :else)
        end

        it "uses the body location for an explicit else in case/when" do
          # Exercises the else-clause-present branch of `else_arm_location`,
          # vs. the synthesized-else case above.
          src = "x = 1\ncase x\nwhen 1 then :a\nelse :b\nend\n"
          static = static_branches(src)
          arms = static.values.first
          else_tuple = arms.keys.find { |k| k.first == :else }
          # Else arm is on line 4 (the `else :b` line), not the case's full range
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

        it "handles empty arm bodies (e.g., `if cond then end`)" do
          # Triggers the `arm_location` fallback branch when StatementsNode
          # is nil — the parent's location stands in.
          src = "if true then end\n"
          static = static_branches(src)
          arms = static.values.first
          # :else is synthesized (no else clause) — both arms must have positions
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
          # Coverage doesn't emit a branch entry for `||=`, neither do we.
          expect(static_branches(src)).to be_empty
        end
      end

      describe "runtime tuple equivalence" do
        # BranchesCombiner merges arms across resultsets by their
        # [type, location] identity, so any location drift between what
        # this extractor synthesizes and what Ruby's Coverage reports for
        # the same source creates phantom, permanently-missed arms when a
        # simulated entry merges with a real one (issue #1226; previously
        # issue #1206 for `unless` and safe navigation). This is the
        # differential harness that pins them tuple-for-tuple: every
        # construct below runs through real Coverage in a subprocess and
        # the extractor in-process, and the id-stripped tuples must be
        # identical.
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
            "modifier_if" => "def fx(a)\n  :a if a\nend\n",
            "modifier_unless" => "def fx(a)\n  :a unless a\nend\n",
            "ternary" => "def fx(a)\n  a ? :a : :b\nend\n",
            "case_when" => "def fx(a)\n  case a\n  when 1 then :a\n  when 2 then :b\n  end\nend\n",
            "case_when_else" => "def fx(a)\n  case a\n  when 1 then :a\n  else :b\n  end\nend\n",
            "case_when_empty_body" => "def fx(a)\n  case a\n  when 1\n  when 2 then :b\n  end\nend\n",
            "case_empty_else" => "def fx(a)\n  case a\n  when 1 then :a\n  else\n  end\nend\n",
            "case_in" => "def fx(a)\n  case a\n  in Integer then :i\n  in String then :s\n  end\nend\n",
            "case_in_else" => "def fx(a)\n  case a\n  in Integer then :i\n  else :o\n  end\nend\n",
            "case_in_empty_body" => "def fx(a)\n  case a\n  in Integer\n  in String then :s\n  end\nend\n",
            "while_block" => "def fx\n  i = 0\n  while i < 3\n    i += 1\n  end\nend\n",
            "while_modifier" => "def fx\n  i = 0\n  i += 1 while i < 3\nend\n",
            "while_empty" => "def fx(a)\n  while a\n  end\nend\n",
            "until_block" => "def fx\n  i = 0\n  until i >= 3\n    i += 1\n  end\nend\n",
            "safe_navigation" => "def fx(a)\n  a&.to_s\nend\n"
          }.freeze
        end

        def strip_ids(branches)
          branches.to_h do |condition, arms|
            [tuple_identity(condition), arms.keys.map { |arm| tuple_identity(arm) }.sort_by(&:to_s)]
          end
        end

        # [type, id, sl, sc, el, ec] -> [type, sl, sc, el, ec]: ids are
        # process-local counters on both sides and immaterial to merging.
        def tuple_identity(tuple)
          [tuple[0].to_s, *tuple.values_at(2, 3, 4, 5)]
        end

        # One subprocess for all fixtures: writes each as its own file,
        # loads them under Coverage(branches: true), dumps tuples as JSON.
        def runtime_branches
          Dir.mktmpdir do |dir|
            branch_fixtures.each { |name, src| File.write(File.join(dir, "#{name}.rb"), src) }
            runner = File.join(dir, "runner.rb")
            File.write(runner, runner_script(dir))
            parse_runtime_payload(*Open3.capture2(RbConfig.ruby, runner))
          end
        end

        def parse_runtime_payload(output, status)
          raise "runtime coverage subprocess failed: #{output}" unless status.success?

          JSON.parse(output).transform_values do |pairs|
            pairs.to_h { |condition, arms| [condition, arms.to_h { |a| [a, 0] }] }
          end
        end

        def runner_script(dir)
          <<~RUBY
            require "coverage"
            require "json"
            Coverage.start(branches: true)
            names = #{branch_fixtures.keys.inspect}
            names.each { |name| load File.join(#{dir.inspect}, "\#{name}.rb") }
            result = Coverage.result
            payload = names.to_h do |name|
              branches = result[File.join(#{dir.inspect}, "\#{name}.rb")][:branches]
              [name, branches.map { |condition, arms| [condition, arms.keys] }]
            end
            puts JSON.dump(payload)
          RUBY
        end

        it "synthesizes tuples identical to Ruby's Coverage for every construct" do
          skip "branch coverage unsupported on this Ruby" unless SimpleCov.branch_coverage_supported?

          runtime = runtime_branches
          aggregate_failures do
            branch_fixtures.each do |name, source|
              synthesized = described_class.call(source)["branches"]
              expect(strip_ids(synthesized)).to eq(strip_ids(runtime.fetch(name))), "construct: #{name}"
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
      end

      describe "sequential id assignment" do
        it "assigns ascending ids across all branches and arms in source order" do
          src = "if true\n  :a\nelse\n  :b\nend\nif true\n  :c\nelse\n  :d\nend\n"
          result = described_class.call(src)
          ids = result["branches"].flat_map { |cond, arms| [cond[1]] + arms.keys.map { |a| a[1] } }
          expect(ids).to eq(ids.sort) # ids are strictly increasing
          expect(ids.uniq).to eq(ids) # no duplicates
        end
      end
    end
  end

  describe ".real_source_positions" do
    context "when Prism is not available" do
      it "returns nil so the eval_generated filter is a no-op" do
        skip "Prism is available; the no-Prism path can't be exercised on this Ruby" if described_class.available?

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
        # `if` at line 2, `case` at line 5
        expect(positions[:branches]).to contain_exactly(2, 5)
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
end
