# frozen_string_literal: true

# `track_tests`, which records the lines each test ran, so that `simplecov
# affected` can pick the tests a change needs. Around every test it diffs
# two of Coverage's snapshots of every file the process loaded, so its cost
# is per test, times every file loaded. Then the map it records is written
# to the resultset, and read back to merge and to answer queries.

require_relative "duel_helper"

# Which lines a test grew, from the snapshots before and after it: most
# files are unchanged, and half of them are gems', outside the project.
# Whether a path is in the project is worked out once a file, in `once`.
duel "track: diff a test's snapshots of 200 files" do
  once do
    @before, @after = DuelFixtures.peeks(200)
    @delta = SimpleCov::TestTracker::Delta.new(root_regex: DuelFixtures::ROOT_REGEX)
    @delta.call(@before, @after)
  end
  @delta.call(@before, @after)
end

# A suite's map of 250 tests over 200 files, written into the resultset,
# and read back for a merge, which records each test's lines again.
# The snapshots themselves, which the benchmark above is handed: a suite
# whose process SimpleCov started Coverage in, for track_tests. A snapshot
# copies every loaded file's counts, so what Coverage is asked to count is
# paid on both sides of every test.
duel_process "track: run 250 tests over 200 files and their gems",
  code: %(load #{File.expand_path("track_suite.rb", __dir__).inspect})

duel "contexts: serialize a map of 250 tests" do
  once { @map = SimpleCov::ContextMap.from_hash(DuelFixtures.context_map_hash(200, 250)) }
  @map.to_h
end

duel "contexts: load a map of 250 tests" do
  once { @hash = DuelFixtures.context_map_hash(200, 250) }
  SimpleCov::ContextMap.from_hash(@hash)
end
