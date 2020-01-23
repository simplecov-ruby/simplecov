# frozen_string_literal: true

module SimpleCov
  # Holds the individual data of a coverage result.
  #
  # This is uniform across coverage criteria as they all have:
  #
  # * total - how many things to cover there are (total relevant loc/branches)
  # * covered - how many of the coverables are hit
  # * missed - how many of the coverables are missed
  # * percent - percentage as covered/missed
  # * strength - average hits per/coverable (will not exist for one shot lines format)
  class CoverageData
    attr_reader :total, :covered, :missed, :strength, :percent

    # Requires only covered, missed and strength to be initialized.
    #
    # Other values are computed by this class.
    def initialize(covered:, missed:, strength: nil)
      @covered  = covered
      @missed   = missed
      @strength = strength
      @total    = covered + missed
      @percent  = compute_percent(covered, total)
    end

    def compute_percent(covered, total)
      return 100.0 if total.zero?

      Float(covered * 100.0 / total)
    end
  end
end
