# frozen_string_literal: true

module SimpleCov
  module Configuration
    TRACK_TESTS_GRANULARITIES = %i[test file].freeze

    # Enables recording of which test covered which line. Off by default:
    # sampling coverage around every test costs run time, and the recorded map
    # costs space in `.resultset.json`. RSpec examples and Minitest tests are
    # wrapped automatically; other runners wrap their own units of work with
    # `SimpleCov.track_test`. A bare `track_tests` enables, and only an explicit
    # `track_tests false` turns it back off.
    #
    # `granularity` decides what one recorded context stands for: a test
    # (`:test`, the default) or a whole test file (`:file`). File granularity is
    # the batching lever for suites where per-test sampling costs too much.
    def track_tests(enabled = nil, granularity: nil)
      if granularity && !TRACK_TESTS_GRANULARITIES.include?(granularity)
        raise ConfigurationError,
              "Unsupported track_tests granularity #{granularity.inspect}, " \
              "supported values are #{TRACK_TESTS_GRANULARITIES.inspect}"
      end

      @track_tests_granularity = granularity if granularity
      @track_tests = enabled.nil? || enabled
    end

    def track_tests?
      !!@track_tests
    end

    def track_tests_granularity
      @track_tests_granularity || :test
    end

    # @api private. The map is built from per-line execution count deltas, which
    # `:oneshot_line` does not produce: a line reports only its first hit ever,
    # so every test after the first would show no delta.
    def validate_test_tracking!
      return unless track_tests?
      return if coverage_criterion_enabled?(DEFAULT_COVERAGE_CRITERION)

      raise ConfigurationError,
            "`track_tests` needs line coverage with execution counts. " \
            "Enable it with `enable_coverage :line` (`:oneshot_line` cannot record per-test data)."
    end
  end
end
