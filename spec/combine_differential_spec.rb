# frozen_string_literal: true

require "helper"
require "support/merge_fuzzer"
require "support/merge_reference"

# Differential test for the whole merge, end to end: `Combine.combine`'s
# short-circuit, `ResultsCombiner`'s fold over files, `FilesCombiner`'s
# reconciliation, and the three leaf combiners. The unit specs for each of
# those live in spec/combine/; this one is about what they add up to.
#
# `ResultsCombiner` folds resultsets pairwise, so what it does to N of them is
# emergent rather than written down anywhere. `MergeReference` states the N-way
# rules directly; this compares the two over generated shard sets built to hit
# the cases the rules turn on (see `MergeFuzzer`).
#
# Its job is to pin the pairwise fold's behaviour precisely enough that it can
# be replaced by a single-pass accumulator without silently changing an answer -
# in particular the `reconcile_synthesized` rule, which is defined on a pair and
# has to be restated N-way to survive that change.
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

  describe "merging N resultsets",
           if: SimpleCov.branch_coverage_supported? && SimpleCov.method_coverage_supported? do
    it "agrees with the reference merge on every generated shard set" do
      mismatches = seeds.filter_map { |seed| mismatch_for(seed, :fold, saturate: true) }

      expect(mismatches).to be_empty, -> { describe_mismatches(mismatches) }
    end

    # Identity collapse only happens inside a combiner, and `Combine.combine`
    # short-circuits before reaching one when either side is nil - handing the
    # other side back verbatim. So a file whose coverage never meets a non-nil
    # counterpart keeps duplicate identities, and the #1233 / #1234 dedup does
    # not apply to it. A resultset with a single command_name is the common
    # case: `merge_coverage` returns it unchanged, so nothing collapses.
    #
    # Pinned here rather than folded into the differential above (which
    # saturates its shard sets to avoid it) so that a change to it has to be
    # deliberate. The consequence is a phantom uncovered method for the #1234
    # shape - one `define_method` landing on two receivers - in a single-suite
    # run.
    it "leaves duplicate identities uncollapsed when the counterpart is nil" do
      duplicate = {["Foo", :call, 2, 2, 4, 10] => 3, ["Bar", :call, 2, 2, 4, 10] => 0}

      expect(described_class.combine(SimpleCov::Combine::MethodsCombiner, duplicate, nil))
        .to eq(duplicate)
      expect(described_class.combine(SimpleCov::Combine::MethodsCombiner, duplicate, {}))
        .to eq(["Foo", :call, 2, 2, 4, 10] => 3)
    end
  end

  def seeds
    1..Integer(ENV.fetch("SIMPLECOV_MERGE_SEEDS", "300"))
  end

  # Returns nil when the fold and the reference agree, otherwise the detail
  # needed to reproduce and read the disagreement.
  def mismatch_for(seed, strategy, saturate:)
    shards = MergeFuzzer.shards(seed, saturate: saturate)
    actual = normalize(send(strategy, shards))
    expected = normalize(MergeReference.call(shards, branches: true, methods: true))
    return nil if actual == expected

    files = expected.keys.union(actual.keys).reject { |file| actual[file] == expected[file] }
    {seed: seed, strategy: strategy, shards: shards, files: files, actual: actual, expected: expected}
  end

  def fold(shards)
    shards.reduce { |a, b| described_class.combine(SimpleCov::Combine::ResultsCombiner, a, b) }
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
    ["seed #{seed} (#{strategy}) — files: #{files.join(', ')}", *detail].join("\n")
  end

  def describe_file(file, mismatch)
    ["  #{file}",
     "    shards:    #{mismatch[:shards].map { |shard| shard[file] }.inspect}",
     "    actual:    #{mismatch[:actual][file].inspect}",
     "    reference: #{mismatch[:expected][file].inspect}"]
  end
end
