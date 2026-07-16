# frozen_string_literal: true

require "helper"
require "support/branch_fuzzer"
require "simplecov/static_coverage_extractor"
require "json"
require "open3"
require "tmpdir"

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
    skip "branch coverage unsupported on this Ruby" unless SimpleCov.branch_coverage_supported?

    programs = BranchFuzzer.programs(seeds: Integer(ENV.fetch("SIMPLECOV_FUZZ_SEEDS", "20")),
                                     per_seed: Integer(ENV.fetch("SIMPLECOV_FUZZ_PER_SEED", "60")))
    runtime = coverage_branches(programs)

    mismatches = programs.filter_map do |name, source|
      source unless extractor_branches(source) == strip_ids(runtime.fetch(name, {}))
    end

    expect(mismatches).to be_empty, lambda {
      "differential mismatch in #{mismatches.length} program(s):\n\n#{mismatches.join("\n---\n")}"
    }
  end

  def extractor_branches(source)
    extracted = described_class.call(source)
    extracted ? strip_ids(extracted["branches"]) : "CRASH"
  end

  # Real Coverage for every program, computed in one subprocess.
  def coverage_branches(programs)
    Dir.mktmpdir do |dir|
      programs.each { |name, source| File.write(File.join(dir, "#{name}.rb"), source) }
      runner = File.join(dir, "runner.rb")
      File.write(runner, runner_script(dir, programs.keys))
      output, _err, status = Open3.capture3(RbConfig.ruby, runner)
      raise "coverage subprocess failed: #{output}" unless status.success?

      parse_runtime(output)
    end
  end

  def parse_runtime(output)
    JSON.parse(output).transform_values { |pairs| pairs.to_h { |cond, arms| [cond, arms.to_h { |arm| [arm, 0] }] } }
  end

  def runner_script(dir, names)
    <<~RUBY
      require "coverage"
      require "json"
      $VERBOSE = nil
      Coverage.start(branches: true)
      names = #{names.inspect}
      names.each { |name| load File.join(#{dir.inspect}, "\#{name}.rb") }
      result = Coverage.result
      payload = names.to_h do |name|
        branches = result.dig(File.join(#{dir.inspect}, "\#{name}.rb"), :branches) || {}
        [name, branches.map { |condition, arms| [condition, arms.keys] }]
      end
      puts JSON.dump(payload)
    RUBY
  end

  # Ids are process-local counters on both sides, so compare on type +
  # position only (matching how BranchesCombiner keys arms).
  def strip_ids(branches)
    branches.to_h do |condition, arms|
      [identity(condition), arms.keys.map { |arm| identity(arm) }.sort_by(&:to_s)]
    end
  end

  def identity(tuple)
    [tuple[0].to_s, *tuple.values_at(2, 3, 4, 5)]
  end
end
