# frozen_string_literal: true

# Phase-by-phase benchmark of `SimpleCov.collate` over a large parallel CI
# run's worth of resultsets, for the configuration such a run uses:
#
#     SimpleCov.collate paths do
#       enable_coverage :branch
#       primary_coverage :branch
#       formatter SimpleCov::Formatter::HTMLFormatter
#       coverage(:line) { minimum_per_file 70 }
#       coverage(:branch) { minimum_per_file 80 }
#     end
#
# Input is synthetic: benchmarks/collate/shape.rb holds the statistics it
# reproduces. Everything — resultsets, source tree, report output
# and timings — lands under the repository's own tmp/collate-benchmark, which
# is left in place between runs and printed at the end of each one.
#
# Usage:
#
#   ruby benchmarks/collate.rb baseline
#   COUNT=8 ruby benchmarks/collate.rb faster --baseline baseline
#   PROCESSES=8 ruby benchmarks/collate.rb parallel --baseline baseline
#
# Environment:
#   COUNT      merge only the first N resultsets — the knob for a fast
#              iteration loop; merge cost grows with N (default: 160)
#   PROCESSES  fan the merge phase out across N forked workers, as
#              `SimpleCov.parallel_collate` does; 1 merges serially (default: 1)
#   SCALE      divide `Shape::FILES` by this (default: 4, giving ~1,836 files;
#              SCALE=1 generates the full 7,345)
#   SKIP       comma-separated trailing phases to skip, e.g. SKIP=format,store
#   REBUILD    1 to regenerate the fixture from scratch
#   BREAKDOWN  1 to also attribute the merge phase to the methods inside it
#              (adds a few percent of overhead — don't use as a baseline)
#
# Timings go to tmp/collate-benchmark/timings/<label>.json, so a later run can
# be compared against them with `--baseline <label>`.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "simplecov"
require_relative "collate/cli"

CollateBenchmark::CLI.run(ARGV) if $PROGRAM_NAME == __FILE__
