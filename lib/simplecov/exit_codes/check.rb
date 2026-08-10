# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    # Shared skeleton for the threshold checks: stash the result and the
    # threshold configuration, fail when any violation exists, and
    # report one message per violation. Subclasses supply `exit_code`,
    # `compute_violations` (memoized here — `failing?` and `report` both
    # consult it), and `report_violation`.
    class Check
      def initialize(result, thresholds)
        @result = result
        @thresholds = thresholds
      end

      def failing?
        violations.any?
      end

      def report
        violations.each { |violation| report_violation(violation) }
      end

    private

      attr_reader :result, :thresholds

      def violations
        @violations ||= compute_violations
      end
    end
  end
end
