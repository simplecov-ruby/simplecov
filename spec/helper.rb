# frozen_string_literal: true

# Dogfood: start Ruby's Coverage module *before* requiring simplecov so
# simplecov's own lib/ files get tracked. Set SIMPLECOV_NO_DOGFOOD=1 to
# skip — useful when running individual specs interactively or when a
# dependency's behaviour around Coverage is being investigated. Skipped
# on Windows because the Unix-only specs we exclude there (cross-process
# flock, `SimpleCov.root("/")`) uniquely cover a handful of lib/ lines,
# so the 100% threshold can't be met from a Windows run alone.
DOGFOOD_DISABLED = ENV["SIMPLECOV_NO_DOGFOOD"] || Gem.win_platform?

unless DOGFOOD_DISABLED
  require "coverage"
  Coverage.start(lines: true, branches: true, methods: true)
end

# `rake spec` fans this suite out through parallel_rspec. Everything
# inside a worker, though — command guessing, final-result detection,
# the sandbox harness, and the subprocesses specs spawn — assumes a
# non-parallel environment. Capture the worker's identity for the few
# helpers that coordinate across workers (per-worker tmp paths, the
# dogfood report's store-and-merge), then scrub the variables so each
# worker is indistinguishable from a serial run on the inside.
SPEC_PARALLEL_WORKER = ENV.fetch("TEST_ENV_NUMBER", nil)
SPEC_PARALLEL_PID_FILE = ENV.fetch("PARALLEL_PID_FILE", nil)
%w[TEST_ENV_NUMBER PARALLEL_TEST_GROUPS PARALLEL_PID_FILE].each { |variable| ENV.delete(variable) }

require "rspec"
require "stringio"
require "open3"
require "tmpdir"
# loaded before simplecov to also capture parse time warnings
require "support/fail_rspec_on_ruby_warning"
require "support/with_env"
require "simplecov"

# Deprecation warnings are deduplicated per source location for the life
# of the process. Reset that state between examples so an earlier example
# warning from a shared location can't suppress a later example that
# asserts the same warning (the suite runs in random order).
RSpec.configure do |config|
  config.before { SimpleCov::Deprecation.reset! }
end

# The default profile chain now includes `test_frameworks`, which
# filters paths under `spec/` — but our unit tests build synthetic
# Results from fixtures under `spec/fixtures/` and assume the filter
# chain doesn't drop them. The dogfood report below still excludes
# the project's own `spec/` via the `extra_filters` list passed to
# `Result.new`, so removing the default here is safe.
SimpleCov.remove_filter %r{\A(test|features|spec|autotest)/}

# Suffixed with the parallel worker number so `rake spec`'s workers
# can't trample each other's caches.
SimpleCov.coverage_dir("tmp/coverage#{SPEC_PARALLEL_WORKER}")

unless DOGFOOD_DISABLED
  # `start_tracking` (not `start`) handles bookkeeping (pid,
  # process_start_time, fork hook) without auto-installing the at_exit
  # formatter — the after(:suite) hook below drives the report
  # ourselves at a controlled point. Filters are passed explicitly to
  # the dogfood `Result.new`, not into `SimpleCov.filters`, so they
  # don't leak into synthetic Results that unit tests build from
  # `spec/fixtures/*` paths.
  SimpleCov.start_tracking

  require "support/dogfood_report"

  RSpec.configure do |config|
    config.after(:suite) { DogfoodReport.generate }
  end
end

# Specs that need real worker processes (see
# spec/parallel_result_merger_spec.rb) are skipped where this is false:
# CRuby on Windows. The in-process merge it falls back to is covered
# everywhere.
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
