# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"

module CoverageDifferential
  extend self

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

  def strip_ids(branches)
    branches.to_h do |condition, arms|
      [tuple_identity(condition), arms.keys.map { |arm| tuple_identity(arm) }.sort_by(&:to_s)]
    end
  end

  def tuple_identity(tuple)
    [tuple[0].to_s, *tuple.values_at(2, 3, 4, 5)]
  end
end
