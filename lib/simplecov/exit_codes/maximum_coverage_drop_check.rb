# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    # Fails when any coverage criterion has dropped by more than the
    # configured maximum since the last recorded run.
    class MaximumCoverageDropCheck
      def initialize(result, maximum_coverage_drop)
        @result = result
        @maximum_coverage_drop = maximum_coverage_drop
      end

      def failing?
        violations.any?
      end

      def report
        violations.each { |violation| ExitCodes.print_error SimpleCov::Color.colorize(message_for(violation), :red) }
      end

      def exit_code
        SimpleCov::ExitCodes::MAXIMUM_COVERAGE_DROP
      end

    private

      # The "drop percent" is a delta, not a coverage level — it has no
      # natural green/yellow/red mapping. Callers color the whole line red
      # so the failure is still visible at a glance.
      def message_for(violation)
        format(
          "%<criterion>s coverage has dropped by %<drop_percent>.2f%% since the last time " \
          "(maximum allowed: %<max_drop>.2f%%).",
          criterion: violation.fetch(:criterion).capitalize,
          drop_percent: violation.fetch(:actual),
          max_drop: violation.fetch(:maximum)
        )
      end

      def violations
        @violations ||= SimpleCov::CoverageViolations.maximum_drop(@result, @maximum_coverage_drop)
      end
    end
  end
end
