# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    # Shared skeleton for the threshold checks: stash the result and the
    # threshold configuration, fail when any violation exists, and
    # answer the report as rendered lines. Subclasses supply
    # `exit_code`, `compute_violations` (memoized here — `failing?` and
    # `report_lines` both consult it), and `violation_lines`.
    class Check
      def initialize(result, thresholds)
        @result = result
        @thresholds = thresholds
      end

      def failing?
        violations.any?
      end

      # The structured violations this check found, as values.
      def violations
        @violations ||= compute_violations
      end

      # The whole report as values, every violation's lines in order,
      # so what a failing check says can be held rather than captured.
      # Concatenated rather than flat-mapped: a check answering a bare
      # string instead of its list of lines is an error this raises,
      # not a spelling the flattening would forgive.
      def report_lines
        lines = [] #: Array[String]
        violations.each_with_object(lines) { |violation, into| into.concat(violation_lines(violation)) }
      end

      # Printing is the one side effect, and it happens here alone.
      def report
        report_lines.each { |line| ExitCodes.print_error(line) }
      end

    private

      attr_reader :result, :thresholds
    end
  end
end
