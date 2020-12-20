# frozen_string_literal: true

module SimpleCov
  module ExitCodes
    class MaximumCoverageDropCheck
      def initialize(result, maximum_coverage_drop)
        @result = result
        @maximum_coverage_drop = maximum_coverage_drop
      end

      def failing?
        return false unless maximum_coverage_drop && last_run

        coverage_drop_violations.any?
      end

      def report
        coverage_drop_violations.each do |violation|
          $stderr.printf(
            "%<criterion>s coverage has dropped by %<drop_percent>.2f%% since the last time (maximum allowed: %<max_drop>.2f%%).\n",
            criterion: violation[:criterion].capitalize,
            drop_percent: SimpleCov.round_coverage(violation[:drop_percent]),
            max_drop: violation[:max_drop]
          )
        end
      end

      def exit_code
        SimpleCov::ExitCodes::MAXIMUM_COVERAGE_DROP
      end

    private

      attr_reader :result, :maximum_coverage_drop

      def last_run
        return @last_run if defined?(@last_run)

        @last_run = SimpleCov::LastRun.read
      end

      def coverage_drop_violations
        @coverage_drop_violations ||=
          compute_coverage_drop_data.select do |achieved|
            achieved.fetch(:max_drop) < achieved.fetch(:drop_percent)
          end
      end

      def compute_coverage_drop_data
        maximum_coverage_drop.map do |criterion, percent|
          {
            criterion: criterion,
            max_drop: percent,
            drop_percent: last_coverage(criterion) -
              SimpleCov.round_coverage(
                result.coverage_statistics.fetch(criterion).percent
              )
          }
        end
      end

      def last_coverage(criterion)
        last_coverage_percent = last_run[:result][criterion]

        if !last_coverage_percent && criterion == "line"
          last_run[:result][:covered_percent]
        else
          last_coverage_percent
        end
      end
    end
  end
end
