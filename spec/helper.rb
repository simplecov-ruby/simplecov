# frozen_string_literal: true

DOGFOOD_DISABLED = ENV["SIMPLECOV_NO_DOGFOOD"] || Gem.win_platform?

unless DOGFOOD_DISABLED
  require "coverage"
  start_args = {lines: true}
  if Coverage.respond_to?(:supported?)
    start_args[:branches] = true if Coverage.supported?(:branches)
    start_args[:methods] = true if Coverage.supported?(:methods)
  else
    start_args[:branches] = true
    start_args[:methods] = true
  end
  Coverage.start(start_args)
end

SPEC_PARALLEL_WORKER = ENV.fetch("TEST_ENV_NUMBER", nil)
SPEC_PARALLEL_PID_FILE = ENV.fetch("PARALLEL_PID_FILE", nil)
PARALLEL_RUNNER_VARIABLES = %w[TEST_ENV_NUMBER PARALLEL_TEST_GROUPS PARALLEL_PID_FILE].freeze
PARALLEL_RUNNER_VARIABLES.each { |variable| ENV.delete(variable) }

%w[FORCE_COLOR NO_COLOR].each { |variable| ENV.delete(variable) }

require "rspec"
require "stringio"
require "open3"
require "timeout"
require "tmpdir"
require "support/fail_rspec_on_ruby_warning"
require "support/with_env"
require "simplecov"

RSpec.configure do |config|
  config.before { SimpleCov::Deprecation.reset! }

  # JRuby on Windows cannot open libprism, so there is no static extraction
  # for these to assert on.
  config.filter_run_excluding :prism unless SimpleCov::StaticCoverageExtractor.prism_loaded?

  config.before do
    next unless defined?(SimpleCov::CLI::Open)

    allow(SimpleCov::CLI::Open).to receive(:system).and_return(true)
    allow(SimpleCov::CLI::Watch).to receive(:spawn).and_return(1234) if defined?(SimpleCov::CLI::Watch)
  end
end

SimpleCov.remove_filter %r{\A(test|features|spec|autotest)/}

SimpleCov.coverage_dir("tmp/coverage#{SPEC_PARALLEL_WORKER}")

unless DOGFOOD_DISABLED
  SimpleCov.track_tests if ENV["SIMPLECOV_TRACK_TESTS"]
  SimpleCov.start_tracking

  require "support/dogfood_report"
  DogfoodReport.announce

  RSpec.configure do |config|
    config.after(:suite) { DogfoodReport.generate }
  end
end

FORK_SUPPORTED = Process.respond_to?(:fork)
JRUBY_ON_WINDOWS = RUBY_ENGINE == "jruby" && Gem.win_platform?

# JRuby on Windows implements flock with a JVM-wide FileChannel lock, which a
# second handle in the same process can neither take nor be refused, so a
# probe from inside the suite says nothing about the lock another process sees.
def skip_same_process_flock_probe
  skip "flock cannot be probed from the same process on JRuby on Windows" if JRUBY_ON_WINDOWS
end

# JRuby on Windows has stalled a worker until the CI job's time limit, and its
# buffered output never said where. An example that outlives this limit fails
# instead, after printing every thread's backtrace to $stdout, which the
# warning collector leaves alone, so a stall costs minutes and names itself.
EXAMPLE_TIME_LIMIT = 180

def run_with_watchdog(example)
  runner = Thread.current
  watchdog = Thread.new do
    sleep(EXAMPLE_TIME_LIMIT)
    report_stalled_example(example)
    runner.raise(Timeout::Error, "ran past #{EXAMPLE_TIME_LIMIT}s")
  end
  example.run
ensure
  watchdog&.kill
end

def report_stalled_example(example)
  $stdout.puts("\n#{example.location} ran past #{EXAMPLE_TIME_LIMIT}s. Every thread:")
  Thread.list.each do |thread|
    $stdout.puts(thread.inspect, *Array(thread.backtrace).first(25).map { |frame| "    #{frame}" })
  end
  $stdout.flush
end

RSpec.configure { |config| config.around { |example| run_with_watchdog(example) } } if JRUBY_ON_WINDOWS

def source_fixture(filename)
  File.join(source_fixture_base_directory, "fixtures", filename)
end

def source_fixture_base_directory
  @source_fixture_base_directory ||= File.dirname(__FILE__)
end

# Open3 rather than `system(..., out: File::NULL)`, whose options JRuby on
# Windows ignores with a warning. JRuby there raises a Java IOException rather
# than Errno::ENOENT for a program that is not installed.
def command_succeeds?(*command)
  Open3.capture2e(*command).last.success?
rescue
  false
end

# The environment for a child process that runs SimpleCov, with the parallel
# runner's variables unset. Deleting them from ENV is not enough on JRuby on
# Windows, whose Open3 builds a child's environment from the one the JVM
# started with, so a child would take itself for a parallel worker.
def child_env(env = {})
  PARALLEL_RUNNER_VARIABLES.to_h { |variable| [variable, nil] }.merge(env)
end

def capture_stderr
  previous_stderr = $stderr
  $stderr = StringIO.new
  yield
  $stderr.string
ensure
  $stderr = previous_stderr
end

def capture_stdout
  previous_stdout = $stdout
  $stdout = StringIO.new
  yield
  $stdout.string
ensure
  $stdout = previous_stdout
end

# capture_stderr and capture_stdout answer what was written; these answer what
# the block returned, for the examples that assert on the value, not the noise.
def without_stderr
  answer = nil
  capture_stderr { answer = yield }
  answer
end

def without_stdout
  answer = nil
  capture_stdout { answer = yield }
  answer
end

# Runs the block for its effect, swallowing the error it is expected to raise,
# so an example about what survives the error needs no expectation for it.
def suppress(klass)
  yield
rescue klass
  nil
end

# Answers the error the block raised, for the examples that ask what an error
# says rather than that it was raised at all.
def capture_error(klass)
  yield
  nil
rescue klass => error
  error
end
