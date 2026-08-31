# frozen_string_literal: true

# Scaling benchmark for the report pipeline: generates a synthetic project of N
# small files, runs SimpleCov over it end to end, and prints per-phase
# wall-clock and GC timings as JSON. Per-file cost should stay flat as N grows.
#
# Usage:
#
#   ruby benchmarks/report_scale.rb 10000
#   ruby benchmarks/report_scale.rb 100000
#
# Everything lands under tmp/report-scale-benchmark/<n>, which is left in place
# so a rerun at the same size skips generation. Generation and the measured run
# happen in a child process so the parent stays free of Coverage state.

require "fileutils"
require "json"

if ENV["REPORT_SCALE_CHILD"]
  project_dir = ENV.fetch("REPORT_SCALE_PROJECT")
  $LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
  GC.measure_total_time = true

  phases = {}
  gc_time = {}
  measure = lambda do |name, &block|
    gc0 = GC.total_time
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = block.call
    phases[name] = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0).round(3)
    gc_time[name] = ((GC.total_time - gc0) / 1_000_000_000.0).round(3)
    result
  end

  require "simplecov"
  SimpleCov.start do
    command_name "ReportScale"
    root project_dir
    coverage_dir File.join(project_dir, "coverage")
    merging false
    formatter false
    enable_coverage :branch
    enable_coverage :method
  end

  files = Dir[File.join(project_dir, "lib", "**", "*.rb")]
  measure.call(:load_and_track) { files.each { |f| require f } }
  result = measure.call(:result_build) { SimpleCov.result }
  measure.call(:grouping) { result.groups }
  measure.call(:statistics) { result.coverage_statistics }
  measure.call(:json_format) { SimpleCov::Formatter::JSONFormatter.new(silent: true).format(result) }
  measure.call(:html_format) { SimpleCov::Formatter::HTMLFormatter.new(silent: true).format(result) }
  measure.call(:store_resultset) { SimpleCov::ResultMerger.store_result(result) }
  measure.call(:merged_result) { SimpleCov::ResultMerger.merged_result }
  measure.call(:exit_checks) do
    result.least_covered_file
    SimpleCov.write_last_run(result)
  end

  puts JSON.pretty_generate(n: files.size, phases: phases, gc_time: gc_time,
                            rss_mb: `ps -o rss= -p #{Process.pid}`.to_i / 1024)
  $stdout.flush
  # Skip at_exit so the report pipeline isn't run a second time.
  exit!(0)
end

n = Integer(ARGV.fetch(0, "10000"))
project_dir = File.expand_path("../tmp/report-scale-benchmark/#{n}", __dir__)
lib_dir = File.join(project_dir, "lib")

unless Dir.exist?(lib_dir) && Dir[File.join(lib_dir, "**", "*.rb")].size == n
  FileUtils.rm_rf(project_dir)
  FileUtils.mkdir_p(lib_dir)
  n.times do |i|
    dir = File.join(lib_dir, format("d%04d", i / 1000))
    FileUtils.mkdir_p(dir) if (i % 1000).zero?
    klass = format("C%07d", i)
    File.write(File.join(dir, format("f%07d.rb", i)), <<~RUBY)
      class #{klass}
        def covered
          value = 1 > 0 ? :yes : :no
          [value, 2].size
        end

        def uncovered
          if value_missing?
            :never
          end
        end

        def value_missing?
          false
        end
      end
      #{klass}.new.covered
    RUBY
  end
  puts "generated #{n} files under #{project_dir}"
end

FileUtils.rm_rf(File.join(project_dir, "coverage"))
env = {"REPORT_SCALE_CHILD" => "1", "REPORT_SCALE_PROJECT" => project_dir}
exec(env, RbConfig.ruby, __FILE__)
