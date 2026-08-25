# frozen_string_literal: true

module SimpleCov
  # The miss-count caps, `maximum_missed` and `maximum_missed_per_file`:
  # the thresholds that speak in absolute counts of uncovered lines,
  # branch arms, or methods rather than in percentages. Kept apart from
  # the percent thresholds in `thresholds.rb` because the two families
  # validate differently (a count is a non-negative Integer, never a
  # percent) even though they store and enforce the same way.
  module Configuration
    #
    # Caps the total number of misses (uncovered lines, branch arms, or
    # methods, per criterion) allowed for the testsuite to pass. Where a
    # percent minimum asks for a ratio, this asks for an absolute
    # burn-down number ("12 uncovered lines left"), which stays
    # meaningful as the codebase grows and shrinks. A bare count targets
    # the primary criterion; a Hash sets per-criterion caps:
    #
    #   SimpleCov.maximum_missed 12
    #   SimpleCov.maximum_missed line: 12, branch: 3
    #
    # Default is empty (disabled).
    #
    def maximum_missed(counts = nil)
      return @maximum_missed ||= {} unless counts

      @maximum_missed = normalized_missed_caps(counts, "maximum_missed")
    end

    #
    # Caps the number of misses any single file may carry. Unlike a
    # percent minimum, which systematically flatters big files (a
    # 2,000-line file at 99% hides 20 misses while a 10-line file at 80%
    # fails over 2), this holds every file to the same absolute budget:
    #
    #   SimpleCov.maximum_missed_per_file 5
    #   SimpleCov.maximum_missed_per_file line: 5, branch: 2
    #
    # Per-path overrides are declared through the `coverage` block's
    # `maximum_missed_per_file N, only: "path"` verb. Files with a
    # baseline entry (see `simplecov ratchet`) are exempt per covered
    # criterion, the same way they are from `minimum_per_file`.
    # Default is empty (disabled).
    #
    def maximum_missed_per_file(counts = nil)
      return @maximum_missed_per_file ||= {} unless counts

      @maximum_missed_per_file = normalized_missed_caps(counts, "maximum_missed_per_file")
    end

    # Returns the per-path overrides set via the `coverage` block's
    # `maximum_missed_per_file N, only: target`.
    def maximum_missed_per_file_overrides
      @maximum_missed_per_file_overrides ||= {}
    end

  private

    # The counts counterpart of `normalized_threshold`: same primary-
    # criterion defaulting and criterion validation, but the values are
    # miss counts rather than percents, so a fractional or negative cap
    # is a configuration error rather than a percent >100 warning.
    def normalized_missed_caps(counts, setting)
      counts = {primary_coverage => counts} if counts.is_a?(Numeric)
      counts.each_key { |criterion| raise_if_criterion_disabled(criterion) }
      counts.each_value { |cap| raise_on_invalid_missed_cap(cap, setting) }
      # The value check just above is what guarantees the Integer values
      # the cast claims.
      _ = counts
    end

    def raise_on_invalid_missed_cap(cap, setting)
      return if cap.is_a?(Integer) && cap >= 0

      raise SimpleCov::ConfigurationError,
            "#{setting} takes a non-negative integer count of misses, got #{cap.inspect}"
    end
  end
end
