# frozen_string_literal: true

# Dogfood: start Ruby's Coverage module *before* requiring simplecov so
# simplecov's own lib/ files get tracked. Set SIMPLECOV_NO_DOGFOOD=1 to
# skip — useful when running individual specs interactively or when a
# dependency's behaviour around Coverage is being investigated.
unless ENV["SIMPLECOV_NO_DOGFOOD"]
  require "coverage"
  Coverage.start(lines: true)
end

require "rspec"
require "stringio"
require "open3"
require "tmpdir"
# loaded before simplecov to also capture parse time warnings
require "support/fail_rspec_on_ruby_warning"
require "simplecov"

SimpleCov.coverage_dir("tmp/coverage")

unless ENV["SIMPLECOV_NO_DOGFOOD"]
  # `start_tracking` (not `start`) handles bookkeeping (pid,
  # process_start_time, fork hook) without auto-installing the at_exit
  # formatter — the after(:suite) hook below drives the report
  # ourselves at a controlled point. Filters are passed explicitly to
  # the dogfood `Result.new`, not into `SimpleCov.filters`, so they
  # don't leak into synthetic Results that unit tests build from
  # `spec/fixtures/*` paths.
  SimpleCov.start_tracking

  DOGFOOD_OUTPUT_DIR = "tmp/dogfood"
  DOGFOOD_MINIMUM_COVERAGE = 100.0

  RSpec.configure do |config|
    config.after(:suite) do
      extra_filters = %w[/spec/ /features/ /test_projects/ /tmp/].map { |path| SimpleCov::StringFilter.new(path) }
      raw = SimpleCov::UselessResultsRemover.call(Coverage.result)
      adapted = SimpleCov::ResultAdapter.call(raw)
      result = SimpleCov::Result.new(adapted, filters: SimpleCov.filters + extra_filters, groups: {})

      SimpleCov::Formatter::HTMLFormatter.new(silent: true, output_dir: DOGFOOD_OUTPUT_DIR).format(result)
      percent = result.covered_percent
      next if percent >= DOGFOOD_MINIMUM_COVERAGE

      $stdout.puts format(
        "Dogfood line coverage (%<actual>.2f%%) is below threshold (%<expected>.2f%%). " \
        "See %<dir>s/index.html",
        actual: percent, expected: DOGFOOD_MINIMUM_COVERAGE, dir: DOGFOOD_OUTPUT_DIR
      )
      Kernel.exit(SimpleCov::ExitCodes::MINIMUM_COVERAGE)
    end
  end
end

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
