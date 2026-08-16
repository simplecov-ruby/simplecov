# frozen_string_literal: true

module SimpleCov
  # The test-context recording mode (`test_contexts :per_test`). Not a
  # coverage criterion: criteria pick `Coverage.start`'s arguments,
  # while context recording samples `Coverage.peek_result` on top of
  # whatever is measured.
  module Configuration
    SUPPORTED_TEST_CONTEXT_MODES = [nil, :per_test].freeze

    # Get or set the test-context recording mode; `nil` (the default)
    # records nothing. An enum rather than a boolean so coarser
    # granularities can be added later.
    def test_contexts(mode = :__no_arg__)
      return defined?(@test_contexts) ? @test_contexts : nil if mode == :__no_arg__

      unless SUPPORTED_TEST_CONTEXT_MODES.include?(mode)
        raise SimpleCov::ConfigurationError,
              "Unsupported test_contexts mode #{mode.inspect}, supported values are " \
              "#{SUPPORTED_TEST_CONTEXT_MODES.compact} (or nil to disable)"
      end

      @test_contexts = mode
    end

    # @api private
    def per_test_contexts?
      test_contexts == :per_test
    end

    # @api private — run by `SimpleCov.start_tracking` before measuring.
    def validate_tracking_configuration!
      validate_coverage_criteria!
      validate_test_contexts!
    end

    # @api private — deltas are hit-count increases, so full line
    # counts are required.
    def validate_test_contexts!
      return unless per_test_contexts?

      require "coverage"
      unless Coverage.respond_to?(:peek_result)
        raise SimpleCov::ConfigurationError,
              "test_contexts :per_test needs Coverage.peek_result, which this Ruby does not provide."
      end

      validate_line_counts_for_test_contexts!
    end

  private

    def validate_line_counts_for_test_contexts!
      if coverage_criterion_enabled?(ONESHOT_LINE_COVERAGE_CRITERION)
        raise SimpleCov::ConfigurationError,
              ":oneshot_line records each line at most once, so per-test deltas cannot be computed. " \
              "Use `enable_coverage :line` together with `test_contexts :per_test`."
      end

      return if coverage_criterion_enabled?(DEFAULT_COVERAGE_CRITERION)

      raise SimpleCov::ConfigurationError,
            "test_contexts :per_test attributes covered lines to tests, so line coverage is required. " \
            "Enable it with `enable_coverage :line`."
    end
  end
end
