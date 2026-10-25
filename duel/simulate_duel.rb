# frozen_string_literal: true

# Simulating coverage for a file that a `cover` or `track_files` glob
# matched but no process loaded: which lines are relevant, with the
# `:nocov:` and `simplecov:disable` ranges taken out, and the branches and
# methods Coverage would have reported, from a Prism parse. A merge does
# this for every such file, so it's per file of a project's untested code.
#
# The sources are real Ruby (duel/fixtures): a typical file, the same file
# with a `simplecov:disable` block, which tokenizes it to find the block,
# and a large one.

require_relative "duel_helper"

duel "simulate: classify a typical file's lines" do
  once { @lines = DuelFixtures.source_lines("typical.rb") }
  SimpleCov::LinesClassifier.new.classify(@lines)
end

duel "simulate: classify lines around directives" do
  once { @lines = DuelFixtures.source_lines("directives.rb") }
  SimpleCov::LinesClassifier.new.classify(@lines)
end

duel "simulate: classify a large file's lines" do
  once { @lines = DuelFixtures.source_lines("large.rb") }
  SimpleCov::LinesClassifier.new.classify(@lines)
end

# Prism loads on the first extraction, in `once`.
duel "simulate: extract a large file's branches" do
  once { @source = DuelFixtures.source_lines("large.rb").join.tap { |source| SimpleCov::StaticCoverageExtractor.call(source) } }
  SimpleCov::StaticCoverageExtractor.call(@source)
end

# The whole of it for one file, as a merge calls it: reading the file, and
# Ruby's own line stub, which compiles it, are system calls and Ruby's
# work, so this one is judged on its counts.
duel "simulate: an unloaded file", only: :count do
  once { @path = DuelFixtures.source_path("typical.rb").tap { |path| SimpleCov::SimulateCoverage.call(path) } }
  SimpleCov::SimulateCoverage.call(@path)
end
