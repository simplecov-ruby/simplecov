# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    class MaximumCoverageDropCheck < Check
      def exit_code
        MAXIMUM_COVERAGE_DROP
      end

      private

      def compute_violations
        CoverageViolations.maximum_drop(result, thresholds)
      end

      # The drop percent is a delta, not a coverage level, so it has no natural
      # green/yellow/red mapping and the whole line goes red.
      def violation_lines(violation)
        [Color.colorize(message_for(violation), :red)]
      end

      def message_for(violation)
        format(
          "%<criterion>s coverage has dropped by %<drop_percent>.2f%% since the last time " \
          "(maximum allowed: %<max_drop>.2f%%).",
          criterion: violation.fetch(:criterion).capitalize,
          drop_percent: violation.fetch(:actual),
          max_drop: violation.fetch(:maximum)
        )
      end
    end
  end
end
