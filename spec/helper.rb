# frozen_string_literal: true

# Dogfood: start Ruby's Coverage module *before* requiring simplecov so
# simplecov's own lib/ files get tracked. Set SIMPLECOV_NO_DOGFOOD=1 to
# skip — useful when running individual specs interactively or when a
# dependency's behaviour around Coverage is being investigated.
unless ENV["SIMPLECOV_NO_DOGFOOD"]
  require "coverage"
  # Build the criteria hash by what the runtime actually supports — JRuby
  # silently ignores `branches:`/`methods:` (with warnings); some engines
  # may reject them outright. CRuby is the primary target so its full
  # set is always on.
  start_args = {lines: true}
  if Coverage.respond_to?(:supported?)
    start_args[:branches] = true if Coverage.supported?(:branches)
    start_args[:methods]  = true if Coverage.supported?(:methods)
  else
    start_args[:branches] = true
    start_args[:methods]  = true
  end
  Coverage.start(start_args)
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

  # Per-engine thresholds. CRuby is the primary target and is held to
  # 100% on every criterion. JRuby and TruffleRuby `skip` specs that
  # exercise branch / method coverage paths their Coverage module
  # doesn't support, so the lib/ lines those specs would have hit stay
  # uncovered there — set the line threshold a hair below today's
  # actual to act as a regression guard rather than a strict ceiling.
  # Engines absent from this hash get an informational report only,
  # no threshold enforcement.
  DOGFOOD_THRESHOLDS = {
    "ruby" => {line: 100.0, branch: 100.0, method: 100.0},
    "jruby" => {line: 97.5},
    "truffleruby" => {line: 97.5}
  }.freeze

  RSpec.configure do |config|
    config.after(:suite) do
      extra_filters = %w[/spec/ /features/ /test_projects/ /tmp/].map { |path| SimpleCov::StringFilter.new(path) }
      raw = SimpleCov::UselessResultsRemover.call(Coverage.result)
      adapted = SimpleCov::ResultAdapter.call(raw)

      # Enabling :branch / :method is what teaches FileList / Result
      # to surface those data in coverage_statistics. We enable here
      # (rather than in SimpleCov.start) to avoid leaking the
      # multi-criterion output shape into formatter specs that assert
      # against line-only fixtures.
      SimpleCov.enable_coverage :branch if SimpleCov.branch_coverage_supported?
      SimpleCov.enable_coverage :method if SimpleCov.method_coverage_supported?
      result = SimpleCov::Result.new(adapted, filters: SimpleCov.filters + extra_filters, groups: {})

      SimpleCov::Formatter::HTMLFormatter.new(silent: true, output_dir: DOGFOOD_OUTPUT_DIR).format(result)

      thresholds = DOGFOOD_THRESHOLDS[RUBY_ENGINE] || {}
      stats = result.coverage_statistics
      shortfalls = thresholds.filter_map do |criterion, expected|
        actual = stats[criterion]&.percent
        next if actual.nil? || actual >= expected

        format("%<criterion>s coverage %<actual>.2f%% (min %<expected>.2f%%)",
               criterion: criterion, actual: actual, expected: expected)
      end
      next if shortfalls.empty?

      $stdout.puts format(
        "Dogfood: %<shortfalls>s. See %<dir>s/index.html",
        shortfalls: shortfalls.join(", "),
        dir: DOGFOOD_OUTPUT_DIR
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
