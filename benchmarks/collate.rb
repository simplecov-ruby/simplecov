# frozen_string_literal: true

# Phase-by-phase benchmark of `SimpleCov.collate` over a large parallel CI run's
# worth of resultsets. Input is synthetic: benchmarks/collate/shape.rb holds the
# statistics it reproduces. Everything lands under tmp/collate-benchmark, which
# is left in place between runs and printed at the end of each one.
#
# Usage:
#
#   ruby benchmarks/collate.rb baseline
#   COUNT=8 ruby benchmarks/collate.rb faster --baseline baseline
#   PROCESSES=8 ruby benchmarks/collate.rb parallel --baseline baseline
#
# Environment:
#   COUNT      merge only the first N resultsets (default: 160)
#   PROCESSES  fan the merge phase out across N forked workers (default: 1)
#   SCALE      divide `Shape::FILES` by this (default: 4, ~1,836 files)
#   SKIP       comma-separated trailing phases to skip, e.g. SKIP=format,store
#   REBUILD    1 to regenerate the fixture from scratch
#   BREAKDOWN  1 to also attribute the merge phase to the methods inside it
#              (adds a few percent of overhead, so not a good baseline)
#
# Timings go to tmp/collate-benchmark/timings/<label>.json, so a later run can
# be compared against them with `--baseline <label>`.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "simplecov"
require_relative "collate/cli"

CollateBenchmark::CLI.run(ARGV) if $PROGRAM_NAME == __FILE__
