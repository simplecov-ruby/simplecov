# frozen_string_literal: true

module SimpleCov
  # Opt-in recording of which test covered each line: `track_tests`.
  module Configuration
    #
    # Enable (or disable, with `track_tests false`) recording of which test
    # covered which line. Off by default: sampling coverage around every
    # test costs run time, and the recorded map costs space in
    # `.resultset.json`.
    #
    #   SimpleCov.start do
    #     track_tests
    #   end
    #
    # RSpec examples and Minitest tests are wrapped automatically. Other
    # runners wrap their own units of work with `SimpleCov.track_test`.
    # The recorded map rides along in `.resultset.json` and is exposed on
    # the result as `SimpleCov::Result#contexts`.
    #
    TRACK_TESTS_GRANULARITIES = %i[test file].freeze

    def track_tests(enabled = nil, granularity: nil)
      if granularity && !TRACK_TESTS_GRANULARITIES.include?(granularity)
        raise ConfigurationError,
              "Unsupported track_tests granularity #{granularity.inspect}, " \
              "supported values are #{TRACK_TESTS_GRANULARITIES.inspect}"
      end

      @track_tests_granularity = granularity if granularity
      # A bare `track_tests` enables; only an explicit `track_tests false`
      # turns it back off.
      @track_tests = enabled.nil? || enabled
    end

    def track_tests?
      !!@track_tests
    end

    # What one recorded context stands for: a test (`:test`, the default)
    # or a whole test file (`:file`). File granularity is the batching
    # lever for suites where per-test sampling costs too much: the
    # recorder pays one coverage snapshot per test file instead of per
    # test, and test selection needs no more than file identity anyway.
    def track_tests_granularity
      @track_tests_granularity || :test
    end

    # @api private — called from `SimpleCov.start_tracking`. The map is
    # built from per-line execution count deltas, which `:oneshot_line`
    # does not produce: a line reports only its first hit ever, so every
    # test after the first would show no delta on lines it exercised.
    def validate_test_tracking!
      return unless track_tests?
      return if coverage_criterion_enabled?(DEFAULT_COVERAGE_CRITERION)

      raise ConfigurationError,
            "`track_tests` needs line coverage with execution counts. " \
            "Enable it with `enable_coverage :line` (`:oneshot_line` cannot record per-test data)."
    end
  end
end
