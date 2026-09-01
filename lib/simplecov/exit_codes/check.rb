# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    # Shared skeleton for the threshold checks. Subclasses supply `exit_code`,
    # `compute_violations` (memoized here, since `failing?` and `report_lines`
    # both consult it), and `violation_lines`.
    class Check
      def initialize(result, thresholds)
        @result = result
        @thresholds = thresholds
      end

      def failing?
        violations.any?
      end

      def violations
        @violations ||= compute_violations
      end

      # Concatenated rather than flat-mapped: a check answering a bare string
      # instead of its list of lines is an error this raises, not a spelling the
      # flattening would forgive.
      def report_lines
        lines = [] #: Array[String]
        violations.each_with_object(lines) { |violation, into| into.concat(violation_lines(violation)) }
      end

      def report
        report_lines.each { |line| ExitCodes.print_error(line) }
      end

      private

      attr_reader :result, :thresholds
    end
  end
end
