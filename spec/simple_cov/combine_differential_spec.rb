# frozen_string_literal: true

require "helper"
require "support/merge_fuzzer"
require "support/merge_reference"

RSpec.describe SimpleCov::Combine do
  around do |example|
    SimpleCov.enable_coverage(:branch)
    SimpleCov.enable_coverage(:method)
    example.run
    SimpleCov.clear_coverage_criteria
  end

  describe "merging N resultsets",
    if: SimpleCov.branch_coverage_supported? && SimpleCov.method_coverage_supported? do
    let(:duplicate) { {["Foo", :call, 2, 2, 4, 10] => 3, ["Bar", :call, 2, 2, 4, 10] => 0} }
    let(:alone) { {"a.rb" => {"lines" => [1], "methods" => duplicate}} }
    let(:counterpart) { {"a.rb" => {"lines" => [1], "methods" => {}}} }

    it "agrees with the reference merge on every generated shard set" do
      mismatches = seeds.filter_map { |seed| mismatch_for(seed, :fold, saturate: true) }

      expect(mismatches).to be_empty, -> { describe_mismatches(mismatches) }
    end

    it "agrees with the reference merge however the fan-out groups the shards" do
      mismatches = seeds.flat_map do |seed|
        groupings.filter_map { |groups| mismatch_for(seed, groups, saturate: true) }
      end

      expect(mismatches).to be_empty, -> { describe_mismatches(mismatches) }
    end

    it "leaves duplicate identities uncollapsed when no other resultset carries the file" do
      expect(fold([alone]).fetch("a.rb")["methods"]).to eq(duplicate)
    end

    it "collapses them once another resultset carries the file" do
      expect(fold([alone, counterpart]).fetch("a.rb")["methods"])
        .to eq(["Foo", :call, 2, 2, 4, 10] => 3)
    end
  end

  def seeds
    1..Integer(ENV.fetch("SIMPLECOV_MERGE_SEEDS", "300"))
  end

  def groupings
    2..5
  end

  def mismatch_for(seed, strategy, saturate:)
    shards = MergeFuzzer.shards(seed, saturate: saturate)
    actual = normalize(merge(shards, strategy))
    expected = normalize(MergeReference.call(shards, branches: true, methods: true))
    return nil if actual == expected

    files = expected.keys.union(actual.keys).reject { |file| actual[file] == expected[file] }
    {seed: seed, strategy: strategy, shards: shards, files: files, actual: actual, expected: expected}
  end

  def merge(shards, strategy)
    return fold(shards) if strategy == :fold

    fold(SimpleCov::ParallelResultMerger.chunk(shards, strategy).map { |slice| fold(slice) })
  end

  def fold(shards)
    SimpleCov::Combine::ResultsCombiner.combine(*shards)
  end

  def normalize(files)
    files.to_h do |file, entry|
      [file, {"lines" => entry["lines"],
              "branches" => entry["branches"] || {},
              "methods" => entry["methods"] || {}}]
    end
  end

  def describe_mismatches(mismatches)
    detail = mismatches.first(3).map { |mismatch| describe_mismatch(mismatch) }
    "#{mismatches.length} seed(s) disagreed with the reference merge " \
      "(#{mismatches.map { |m| m[:seed] }.first(20).join(", ")}):\n\n#{detail.join("\n")}"
  end

  def describe_mismatch(mismatch)
    seed, strategy, files = mismatch.values_at(:seed, :strategy, :files)
    detail = files.flat_map { |file| describe_file(file, mismatch) }
    ["seed #{seed} (#{strategy_label(strategy)}) — files: #{files.join(", ")}", *detail].join("\n")
  end

  def strategy_label(strategy)
    (strategy == :fold) ? "serial fold" : "fan-out over #{strategy} slices"
  end

  def describe_file(file, mismatch)
    ["  #{file}",
      "    shards:    #{mismatch[:shards].map { |shard| shard[file] }.inspect}",
      "    actual:    #{mismatch[:actual][file].inspect}",
      "    reference: #{mismatch[:expected][file].inspect}"]
  end
end
