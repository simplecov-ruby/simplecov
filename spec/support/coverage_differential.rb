# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"

# Shared harness for the differential specs that pin
# `StaticCoverageExtractor`'s synthesized branch tuples against the
# running Ruby's real `Coverage`: each program is written to its own
# file, all are loaded under `Coverage.start(branches: true)` in ONE
# subprocess, and the tuples come back id-stripped, keyed the way
# `BranchesCombiner` keys arms. Used by the deterministic construct
# battery and the opt-in fuzzer alike, so a divergence found by one can
# be replayed verbatim in the other.
module CoverageDifferential
module_function

  # { name => source } -> { name => { condition => { arm => 0 } } }
  def runtime_branches(programs)
    Dir.mktmpdir do |dir|
      programs.each { |name, source| File.write(File.join(dir, "#{name}.rb"), source) }
      runner = File.join(dir, "runner.rb")
      File.write(runner, runner_script(dir, programs.keys))
      output, err, status = Open3.capture3(RbConfig.ruby, runner)
      raise "runtime coverage subprocess failed: #{output}#{err}" unless status.success?

      parse_runtime(output)
    end
  end

  def parse_runtime(output)
    JSON.parse(output).transform_values { |pairs| pairs.to_h { |cond, arms| [cond, arms.to_h { |arm| [arm, 0] }] } }
  end

  # `$VERBOSE = nil` because generated and fixture programs freely use
  # literals in conditions ("string literal in condition" and friends);
  # the nil-safe dig covers programs Coverage records no branches for.
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
      [tuple_identity(condition), arms.keys.map { |arm| tuple_identity(arm) }.sort_by(&:to_s)]
    end
  end

  # [type, id, sl, sc, el, ec] -> [type, sl, sc, el, ec]
  def tuple_identity(tuple)
    [tuple[0].to_s, *tuple.values_at(2, 3, 4, 5)]
  end
end
