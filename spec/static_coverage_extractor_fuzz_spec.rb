# frozen_string_literal: true

require "helper"
require "support/branch_fuzzer"
require "support/coverage_differential"
require "simplecov/static_coverage_extractor"

RSpec.describe SimpleCov::StaticCoverageExtractor, if: ENV.fetch("SIMPLECOV_FUZZ", nil), mutant: false do
  it "synthesizes tuples identical to Coverage across fuzzed programs" do
    skip "branch coverage unsupported on this Ruby" unless SimpleCov.branch_coverage_supported?

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

  def coverage_branches(programs)
    CoverageDifferential.runtime_branches(programs)
  end
end
