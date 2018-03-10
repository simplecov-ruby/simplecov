# frozen_string_literal: true

require "benchmark/ips"
require "coverage"

Coverage.start
# such meta, many wow
require_relative "../lib/simplecov"
require_relative "../spec/faked_project/lib/faked_project"
result = Coverage.result

class MyFormatter
  def format(result)
    result.files.map do |file|
      "#{file.filename}: #{file.covered_percent} #{file.lines_of_code}"
    end
    result.covered_percent.to_s
  end
end

SimpleCov.command_name "Benchmarking"
SimpleCov.formatter = MyFormatter

Benchmark.ips do |bm|
  bm.report "generating a simplecov result" do
    SimpleCov::Result.new(result).format!
  end
end
