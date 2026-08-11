# frozen_string_literal: true

require "helper"
require "support/merge_fuzzer"
require "support/merge_reference"

# Differential test for the whole merge, end to end: `CoverageAccumulator`'s
# fold over files, `MergedFile`'s reconciliation, and the three leaf combiners.
# The unit specs for each of those live in spec/combine/; this one is about
# what they add up to.
#
# What the accumulator does to N resultsets is emergent rather than written
# down anywhere. `MergeReference` states the N-way rules directly; this
# compares the two over generated shard sets built to hit the cases the rules
# turn on (see `MergeFuzzer`).
#
# It was written against the pairwise fold the accumulator replaced, to pin
# that behaviour precisely enough that the replacement could not silently
# change an answer - in particular the `reconcile_synthesized` rule, which was
# defined on a pair and had to be restated N-way to survive the change.
#
# Seeds are fixed so CI is deterministic. SIMPLECOV_MERGE_SEEDS raises the
# count for a local soak; a failure prints the seed to replay.
RSpec.describe SimpleCov::Combine do
  around do |example|
    SimpleCov.enable_coverage(:branch)
    SimpleCov.enable_coverage(:method)
    example.run
    SimpleCov.clear_coverage_criteria
  end

  describe "merging N resultsets" do
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

    # Identity collapse happens in `MergedFile`, and the accumulator only
    # promotes a file to one on its second sighting - the first is kept exactly
    # as it came in. So a file no other resultset carries keeps its duplicate
    # identities, and the #1233 / #1234 dedup does not apply to it. A single
    # resultset is the common case, and nothing collapses in it.
    #
    # Pinned here rather than folded into the differential above (which
    # saturates its shard sets to avoid it) so that a change to it has to be
    # deliberate. The consequence is a phantom uncovered method for the #1234
    # shape - one `define_method` landing on two receivers - in a single-suite
    # run.
    it "leaves duplicate identities uncollapsed when no other resultset carries the file" do
      duplicate = {["Foo", :call, 2, 2, 4, 10] => 3, ["Bar", :call, 2, 2, 4, 10] => 0}
      alone = {"a.rb" => {"lines" => [1], "methods" => duplicate}}
      counterpart = {"a.rb" => {"lines" => [1], "methods" => {}}}

      expect(fold([alone]).fetch("a.rb")["methods"]).to eq(duplicate)
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

  # Returns nil when the merge and the reference agree, otherwise the detail
  # needed to reproduce and read the disagreement.
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

  # Only the criteria matter, not which keys a coverage happens to carry.
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
      "(#{mismatches.map { |m| m[:seed] }.first(20).join(', ')}):\n\n#{detail.join("\n")}"
  end

  def describe_mismatch(mismatch)
    seed, strategy, files = mismatch.values_at(:seed, :strategy, :files)
    detail = files.flat_map { |file| describe_file(file, mismatch) }
    ["seed #{seed} (#{strategy_label(strategy)}) — files: #{files.join(', ')}", *detail].join("\n")
  end

  def strategy_label(strategy)
    strategy == :fold ? "serial fold" : "fan-out over #{strategy} slices"
  end

  def describe_file(file, mismatch)
    ["  #{file}",
     "    shards:    #{mismatch[:shards].map { |shard| shard[file] }.inspect}",
     "    actual:    #{mismatch[:actual][file].inspect}",
     "    reference: #{mismatch[:expected][file].inspect}"]
  end
end
