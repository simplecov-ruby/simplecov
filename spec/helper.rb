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
%w[TEST_ENV_NUMBER PARALLEL_TEST_GROUPS PARALLEL_PID_FILE].each { |variable| ENV.delete(variable) }

%w[FORCE_COLOR NO_COLOR].each { |variable| ENV.delete(variable) }

require "rspec"
require "stringio"
require "open3"
require "tmpdir"
require "support/fail_rspec_on_ruby_warning"
require "support/with_env"
require "simplecov"

RSpec.configure do |config|
  config.before { SimpleCov::Deprecation.reset! }

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

  RSpec.configure do |config|
    config.after(:suite) { DogfoodReport.generate }
  end
end

FORK_SUPPORTED = Process.respond_to?(:fork)

def source_fixture(filename)
  File.join(source_fixture_base_directory, "fixtures", filename)
end

def source_fixture_base_directory
  @source_fixture_base_directory ||= File.dirname(__FILE__)
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
