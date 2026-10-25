# frozen_string_literal: true

# Building the report at the end of a run: the coverage Ruby answers,
# adapted, then a Result of SourceFiles with their per-file statistics,
# and the hash that both the JSON and the HTML report are written from.
#
# A SourceFile memoizes everything it works out, so each iteration gets a
# Result of its own, built with `untimed`. Building one checks that every
# file exists, and a SourceFile reads its source as it's first asked for:
# both are system calls, so they're untimed too, apart from the benchmark
# of building the Result itself, which is judged on its counts.

require_relative "duel_helper"

setup do
  @root, @coverage = DuelFixtures.project(200)
  SimpleCov.root(@root)
end

# `Coverage.result` adapted, as at the end of every process: method keys
# renamed by their receiver and grouped by location, branches deduplicated.
# Adapting changes the coverage in place, so each iteration gets its own.
duel "result: adapt a Coverage.result of 200 files" do |n|
  raw = untimed { Array.new(n) { DuelFixtures.raw_coverage(200) } }
  raw.each { |coverage| SimpleCov::ResultAdapter.call(coverage) }
end

# The merged Result of a collate, which drops a file that's gone, and
# applies the configured filters. Checking that each file exists is a
# system call, so this one is judged on its counts.
duel "result: build the merged Result of 200 files", only: :count do
  SimpleCov::ResultMerger.create_result(["RSpec"], @coverage, tracked_files: [])
end

duel "result: statistics of 20 files" do |n|
  once { @small = @coverage.first(20).to_h }
  results = untimed { Array.new(n) { DuelFixtures.loaded_result(@small) } }
  results.each(&:coverage_statistics)
end

# The project's largest file: over a thousand lines and ninety branches.
duel "result: statistics of a large file" do |n|
  once { @large = [DuelFixtures.largest_file(@coverage)].to_h }
  results = untimed { Array.new(n) { DuelFixtures.loaded_result(@large) } }
  results.each(&:coverage_statistics)
end

# Each file's section of the report, the work that grows with a project.
# The document around them also records the git commit, which takes a
# subprocess, so the whole document is judged on its counts.
duel "report: JSON of 20 files" do |n|
  once { @small = @coverage.first(20).to_h }
  results = untimed { Array.new(n) { DuelFixtures.loaded_result(@small) } }
  results.each { |result| DuelFixtures.file_sections(result, include_source: false) }
end

# The HTML report's data, which carries every line of source.
duel "report: HTML data of 20 files" do |n|
  once { @small = @coverage.first(20).to_h }
  results = untimed { Array.new(n) { DuelFixtures.loaded_result(@small) } }
  results.each { |result| DuelFixtures.file_sections(result, include_source: true) }
end

duel "report: the JSON document of 20 files", only: :count do |n|
  once { @small = @coverage.first(20).to_h }
  results = untimed { Array.new(n) { DuelFixtures.loaded_result(@small) } }
  results.each { |result| SimpleCov::Formatter::JSONFormatter.build_hash(result, include_source: false) }
end
