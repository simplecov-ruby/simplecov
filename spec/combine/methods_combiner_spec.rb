# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::Combine::MethodsCombiner do
  describe ".combine" do
    it "sums coverage for matching method keys" do
      coverage_a = {
        '["A", :method1, 2, 2, 5, 5]' => 3,
        '["A", :method2, 9, 2, 11, 5]' => 0
      }
      coverage_b = {
        '["A", :method1, 2, 2, 5, 5]' => 2,
        '["A", :method2, 9, 2, 11, 5]' => 1
      }

      result = described_class.combine(coverage_a, coverage_b)

      expect(result).to eq(
        '["A", :method1, 2, 2, 5, 5]' => 5,
        '["A", :method2, 9, 2, 11, 5]' => 1
      )
    end

    it "preserves methods unique to one side" do
      coverage_a = {'["A", :method1, 2, 2, 5, 5]' => 1}
      coverage_b = {'["B", :method2, 9, 2, 11, 5]' => 2}

      result = described_class.combine(coverage_a, coverage_b)

      expect(result).to eq(
        '["A", :method1, 2, 2, 5, 5]' => 1,
        '["B", :method2, 9, 2, 11, 5]' => 2
      )
    end

    it "works with real array keys (not yet JSON-stringified)" do
      coverage_a = {["A", :method1, 2, 2, 5, 5] => 1}
      coverage_b = {["A", :method1, 2, 2, 5, 5] => 4}

      result = described_class.combine(coverage_a, coverage_b)

      expect(result).to eq(["A", :method1, 2, 2, 5, 5] => 5)
    end

    it "matches methods on source identity, ignoring the receiver class" do
      # The same define_method block lands on different receivers in
      # different processes (one worker's specs define it on a Class, the
      # other's on a Struct). Same (name, location) = same source method;
      # keeping both would let the never-called receiver's 0 count as a
      # separate uncovered method (issue #1234).
      coverage_a = {'["#<Class:0x0>", :inspect, 3, 39, 3, 51]' => 2}
      coverage_b = {'["SomeNamedClass", :inspect, 3, 39, 3, 51]' => 0}

      result = described_class.combine(coverage_a, coverage_b)

      expect(result).to eq('["#<Class:0x0>", :inspect, 3, 39, 3, 51]' => 2)
    end

    it "keeps same-named methods at different locations separate" do
      coverage_a = {'["A", :call, 2, 2, 4, 5]' => 1}
      coverage_b = {'["B", :call, 8, 2, 10, 5]' => 3}

      result = described_class.combine(coverage_a, coverage_b)

      expect(result.values).to contain_exactly(1, 3)
    end

    it "matches different generated names at the same location" do
      # One define_method block generating several names (a builder looping
      # over a container): same location = same source method (issue #1234).
      coverage_a = {'["#<Builder:0x0>", :echo, 38, 26, 41, 11]' => 1}
      coverage_b = {'["#<Builder:0x0>", :bind, 38, 26, 41, 11]' => 0}

      result = described_class.combine(coverage_a, coverage_b)

      expect(result).to eq('["#<Builder:0x0>", :echo, 38, 26, 41, 11]' => 1)
    end

    it "sums duplicated identities arriving within one side" do
      # A resultset stored by an older SimpleCov can still carry
      # per-receiver duplicates; merging must collapse them too.
      coverage_a = {
        '["ClassA", :method_added, 18, 55, 22, 9]' => 6,
        '["ModuleB", :method_added, 18, 55, 22, 9]' => 0
      }

      result = described_class.combine(coverage_a, {})

      expect(result).to eq('["ClassA", :method_added, 18, 55, 22, 9]' => 6)
    end
  end
end
