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
require "support/with_env"
require "simplecov"

# The default profile chain now includes `test_frameworks`, which
# filters paths under `spec/` — but our unit tests build synthetic
# Results from fixtures under `spec/fixtures/` and assume the filter
# chain doesn't drop them. The dogfood report below still excludes
# the project's own `spec/` via the `extra_filters` list passed to
# `Result.new`, so removing the default here is safe.
SimpleCov.remove_filter %r{\A(test|features|spec|autotest)/}

SimpleCov.coverage_dir("tmp/coverage")

unless DOGFOOD_DISABLED
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
    "jruby" => {line: 96.5},
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

      # Leading newline so the formatter's message doesn't fuse onto
      # RSpec's progress-formatter dots when run via `rake spec` / `rspec`.
      # Route through the real STDERR rather than `$stderr` so the
      # formatter's `warn`-based status line and any threshold-violation
      # output survive the FailOnWarnings capture that's installed for
      # the suite (`spec/support/fail_rspec_on_ruby_warning.rb` swaps
      # `$stderr` to a StringIO). Without this, the dogfood report (a
      # contributor-facing health check, not a Ruby warning) would be
      # silently dumped into `tmp/warnings.txt`.
      previous_stderr = $stderr
      $stderr = STDERR
      $stdout.puts

      begin
        SimpleCov::Formatter::HTMLFormatter.new(output_dir: DOGFOOD_OUTPUT_DIR).format(result)

        # Route shortfalls through the same ExitCodeHandling path production
        # uses, so contributors see the dogfood report in exactly the format
        # end users see when minimum_coverage trips: per-criterion violation
        # lines, lowest-coverage files, and the "SimpleCov failed with exit"
        # summary. ExitCodeHandling.call just needs an object that responds
        # to the four limit readers — building a local Struct keeps this
        # helper's coupling to internal API minimal.
        limits = Struct.new(
          :minimum_coverage, :minimum_coverage_by_file, :minimum_coverage_by_file_overrides,
          :minimum_coverage_by_group, :maximum_coverage, :maximum_coverage_drop,
          keyword_init: true
        ).new(
          minimum_coverage: DOGFOOD_THRESHOLDS[RUBY_ENGINE] || {},
          minimum_coverage_by_file: {},
          minimum_coverage_by_file_overrides: {},
          minimum_coverage_by_group: {},
          maximum_coverage: {},
          maximum_coverage_drop: {}
        )
        exit_status = SimpleCov::ExitCodes::ExitCodeHandling.call(result, coverage_limits: limits)
        next unless exit_status.positive?

        warn "SimpleCov failed with exit #{exit_status} due to a coverage related error"
        Kernel.exit(exit_status)
      ensure
        $stderr = previous_stderr
      end
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
