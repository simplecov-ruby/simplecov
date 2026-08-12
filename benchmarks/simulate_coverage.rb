# frozen_string_literal: true

# What it costs to simulate coverage for tracked-but-unloaded files — the
# work `SimpleCov.result` does at exit for every file a
# `cover` glob matched that the process never loaded.
#
# This is per process, so a parallel run pays it once per worker, and each
# worker loads only a fraction of the code: nearly every worker simulates
# nearly the whole project.
#
# The two reports are the two configurations that matter. Branch and method
# coverage are opt-in, and when neither is on, the statically derived
# branch/method tuples are never read — so that run skips the Prism parse
# and only classifies lines.
#
# The corpus is SimpleCov's own lib/, so there is no fixture to build.
#
# Usage:
#
#   ruby benchmarks/simulate_coverage.rb

require "benchmark/ips"
require "coverage"
require_relative "../lib/simplecov"

FILES = Dir[File.expand_path("../lib/**/*.rb", __dir__)]
LINES = FILES.sum { |file| File.foreach(file).count }

puts "#{FILES.size} files, #{LINES} lines"

Benchmark.ips do |bm|
  bm.report "line coverage only (default)" do
    FILES.each { |file| SimpleCov::SimulateCoverage.call(file, synthesize: false) }
  end

  bm.report "branch / method coverage enabled" do
    FILES.each { |file| SimpleCov::SimulateCoverage.call(file, synthesize: true) }
  end

  bm.compare!
end
