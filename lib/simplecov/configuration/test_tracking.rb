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
    def track_tests(enabled = nil)
      # A bare `track_tests` enables; only an explicit `track_tests false`
      # turns it back off.
      @track_tests = enabled.nil? || enabled
    end

    def track_tests?
      defined?(@track_tests) ? !!@track_tests : false
    end

    # @api private — called from `SimpleCov.start_tracking`. The map is
    # built from per-line execution count deltas, which `:oneshot_line`
    # does not produce: a line reports only its first hit ever, so every
    # test after the first would show no delta on lines it exercised.
    def validate_test_tracking!
      return unless track_tests?
      return if coverage_criterion_enabled?(DEFAULT_COVERAGE_CRITERION)

      raise SimpleCov::ConfigurationError,
            "`track_tests` needs line coverage with execution counts. " \
            "Enable it with `enable_coverage :line` (`:oneshot_line` cannot record per-test data)."
    end
  end
end
