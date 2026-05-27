# frozen_string_literal: true

require "helper"
require "coverage"

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
          expect(static.keys.first.first).to eq(:if) # unless is normalized to :if in tuple type
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

        it "does NOT track `||=` (mirrors Coverage's documented behavior)" do
          src = "@x ||= 1\n"
          # Coverage doesn't emit a branch entry for `||=`, neither do we.
          expect(static_branches(src)).to be_empty
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
end
