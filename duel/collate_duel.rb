# frozen_string_literal: true

# Collating a parallel run's resultsets (`SimpleCov.collate`, and the merge
# at the end of every parallel run), the cost that grows with a CI run's
# worker count. Reading each resultset is JSON parsing, and merging it is
# folding its counts into an accumulator that's updated in place, one
# resultset at a time.
#
# The tuple combiners intern every branch key the first time they see it,
# in caches that last the process's life: the first `once` of each
# benchmark warms them, as the first resultset of a real collate does.

require_relative "duel_helper"

# What each further resultset of a run costs: its counts folded into what
# the run's earlier resultsets merged. The counts grow with every
# iteration, but the work doesn't.
duel "collate: absorb a shard of 20 files" do
  once do
    @shards = DuelFixtures.shards(20, 3)
    @accumulator = SimpleCov::Combine::CoverageAccumulator.new
    @shards.first(2).each { |shard| @accumulator.absorb(shard) }
  end
  @accumulator.absorb(@shards.last)
end

duel "collate: absorb a shard of 200 files" do
  once do
    @shards = DuelFixtures.shards(200, 3)
    @accumulator = SimpleCov::Combine::CoverageAccumulator.new
    @shards.first(2).each { |shard| @accumulator.absorb(shard) }
  end
  @accumulator.absorb(@shards.last)
end

# A whole merge of two shards, from a fresh accumulator: each file's
# first merge sets up its tables, and the merged coverage is turned back
# into the shape a Result reads. The merge holds one resultset at a time,
# whatever the run's size, so its memory is guarded too.
duel "collate: merge two shards of 200 files", peak_memory: true do
  once { @shards = DuelFixtures.shards(200, 2).tap { |shards| SimpleCov::Combine::ResultsCombiner.combine(*shards) } }
  SimpleCov::Combine::ResultsCombiner.combine(*@shards)
end

# The merged coverage, from tables keyed by interned identities back to
# the tuple-keyed hashes the rest of SimpleCov reads. Done once a merge.
duel "collate: materialize 200 merged files" do
  once do
    @accumulator = SimpleCov::Combine::CoverageAccumulator.new
    DuelFixtures.shards(200, 3).each { |shard| @accumulator.absorb(shard) }
  end
  @accumulator.result
end

duel "collate: decode a resultset of 20 files" do
  once { @json = DuelFixtures.resultset_json(20) }
  SimpleCov::ResultMerger::ResultsetFile.decode(@json)
end

duel "collate: decode a resultset of 200 files" do
  once { @json = DuelFixtures.resultset_json(200) }
  SimpleCov::ResultMerger::ResultsetFile.decode(@json)
end
