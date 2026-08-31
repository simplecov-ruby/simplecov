# frozen_string_literal: true

module SimpleCov
  # One coverage criterion's numbers, uniform across criteria: total, covered,
  # missed, omitted (only meaningful for line coverage), percent, and strength,
  # the average hits per coverable unit, which the oneshot-lines format has no
  # way to produce.
  class CoverageStatistics
    attr_reader :total, :covered, :missed, :omitted, :strength, :percent

    ZERO_STATS = [0, 0, 0, 0.0].freeze #: [Integer, Integer, Integer, Float]

    # Strength is remultiplied by loc because files have different strengths and
    # line counts, giving them a different weight in the total.
    def self.from(coverage_statistics)
      sum_covered, sum_missed, sum_omitted, sum_total_strength =
        coverage_statistics.reduce(ZERO_STATS) do |(covered, missed, omitted, total_strength), stats|
          [
            covered + stats.covered,
            missed + stats.missed,
            omitted + stats.omitted,
            total_strength + (stats.strength * stats.total)
          ]
        end

      new(covered: sum_covered, missed: sum_missed, omitted: sum_omitted, total_strength: sum_total_strength)
    end

    def initialize(covered:, missed:, omitted: 0, total_strength: 0, percent: nil)
      @covered  = covered
      @missed   = missed
      @omitted  = omitted
      @total    = covered + missed
      @percent  = percent || compute_percent(covered, missed, total)
      @strength = compute_strength(total_strength, total)
    end

  private

    def compute_percent(covered, missed, total)
      return 100.0 if missed.zero?

      covered * 100.0 / total
    end

    def compute_strength(total_strength, total)
      return 0.0 if total.zero?

      total_strength.fdiv(total)
    end
  end
end
