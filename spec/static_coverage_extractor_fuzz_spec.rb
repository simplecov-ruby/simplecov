# frozen_string_literal: true

require "helper"
require "support/branch_fuzzer"
require "support/coverage_differential"
require "simplecov/static_coverage_extractor"

# Differential fuzzer for StaticCoverageExtractor.
#
# SimulateCoverage merges the extractor's synthesized branch tuples into the
# real ones Coverage produces, keyed by [type, start/end line/col]. Any drift
# between the two — for a construct, nesting, or Ruby version the hand
# fixtures don't cover — leaves a phantom, permanently-missed branch after
# merge (issues #1226, #1233, and the audit that followed).
#
# This generates thousands of small `def` bodies mixing every branch
# construct Prism emits (see BranchFuzzer), runs each through real
# Coverage(branches: true) in a subprocess AND through the extractor
# in-process, and asserts the id-stripped tuples are identical. Because it
# compares against the running Ruby's Coverage, it pins version-specific
# conventions automatically on whichever Ruby (and Prism) CI runs.
#
# It's slow (a subprocess per sweep) and randomized, so it's opt-in: set
# SIMPLECOV_FUZZ=1 to run it. SIMPLECOV_FUZZ_SEEDS / SIMPLECOV_FUZZ_PER_SEED
# tune the volume; a failure prints the offending source so it can be copied
# into the deterministic spec.
RSpec.describe SimpleCov::StaticCoverageExtractor, if: ENV.fetch("SIMPLECOV_FUZZ", nil) do
  it "synthesizes tuples identical to Coverage across fuzzed programs" do
    programs = BranchFuzzer.programs(seeds: Integer(ENV.fetch("SIMPLECOV_FUZZ_SEEDS", "20")),
                                     per_seed: Integer(ENV.fetch("SIMPLECOV_FUZZ_PER_SEED", "60")))
    runtime = coverage_branches(programs)

    mismatches = programs.filter_map do |name, source|
      source unless extractor_branches(source) == CoverageDifferential.strip_ids(runtime.fetch(name, {}))
    end

    expect(mismatches).to be_empty, lambda {
      "differential mismatch in #{mismatches.length} program(s):\n\n#{mismatches.join("\n---\n")}"
    }
  end

  def extractor_branches(source)
    extracted = described_class.call(source)
    extracted ? CoverageDifferential.strip_ids(extracted["branches"]) : "CRASH"
  end

  # Real Coverage for every program, computed in one subprocess.
  def coverage_branches(programs)
    CoverageDifferential.runtime_branches(programs)
  end
end
