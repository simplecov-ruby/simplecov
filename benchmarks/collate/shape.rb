# frozen_string_literal: true

module CollateBenchmark
  # The reference shape of a large parallel CI run's coverage artifacts, and
  # the whole of what the fixture is built from. Every field is an aggregate —
  # no filenames, no source, no coverage values.
  #
  # `scale` divides `FILES` only. Every other field is a per-file distribution
  # or a ratio, so a scale of 4 yields a quarter of the lines, conditions and
  # branch arms too, keeping the combiner hotspots in the same proportion as a
  # full-size run.
  module Shape
    RESULTSETS = 160

    FILES = 7345
    # Headline totals. The sampled distributions are fitted to these so a
    # fixture reports exactly `total / scale`, rather than whatever the
    # trapezoidal approximation of a convex quantile curve happens to give
    # (which ran 2-5% high).
    LINES = 591_499
    CONDITIONS = 32_820

    # Lines-per-file quantiles (mean 80.5). Sampled through a
    # piecewise-linear inverse CDF so the synthetic size distribution matches
    # rather than clustering on the mean. The curve is dense through the upper
    # tail on purpose: both this and the condition distribution are sharply
    # convex above p90, and interpolating that stretch from p90 straight to
    # the maximum overstates the totals by more than 20%.
    LINES_PER_FILE = {0.0 => 3, 0.05 => 11, 0.10 => 15, 0.20 => 24, 0.30 => 32, 0.40 => 39,
                      0.50 => 48, 0.60 => 61, 0.70 => 78, 0.80 => 107, 0.85 => 129,
                      0.90 => 166, 0.94 => 222, 0.97 => 322, 0.99 => 554, 0.995 => 721,
                      0.999 => 1300, 1.0 => 2615}.freeze

    # Of all lines, the share Coverage reports a count for. The rest are
    # `nil`: comments, blanks, `end` keywords.
    RELEVANT_LINE_FRACTION = 0.4009
    # Of those, the share with a non-zero count in a *single* shard.
    COVERED_RELEVANT_FRACTION = 0.4232
    # Non-zero counts are overwhelmingly 1 (p90 == 1, p99 == 8), with a long
    # tail up to six figures for hot framework paths. The tail matters because
    # it is what makes the JSON payload realistically wide.
    HIT_COUNT_TAIL = {1 => 0.90, 8 => 0.09, 105_077 => 0.01}.freeze

    BRANCHY_FILE_FRACTION = 0.659
    # Conditions per file, counting only files that have any (mean 6.79).
    CONDITIONS_PER_BRANCHY_FILE = {0.0 => 1, 0.05 => 1, 0.10 => 1, 0.20 => 1, 0.30 => 2,
                                   0.40 => 3, 0.50 => 3, 0.60 => 5, 0.70 => 6, 0.80 => 9,
                                   0.85 => 11, 0.90 => 15, 0.94 => 20, 0.97 => 31, 0.99 => 51,
                                   0.995 => 77, 0.999 => 140, 1.0 => 246}.freeze

    # Arms-per-condition tally, verbatim (sums to 32,820 conditions). Sampled
    # by weight, which reproduces the mean of 2.059 without hand-tuning.
    ARMS_PER_CONDITION = {1 => 70, 2 => 31_872, 3 => 406, 4 => 249, 5 => 97, 6 => 48,
                          7 => 29, 8 => 14, 9 => 9, 10 => 5, 11 => 2, 12 => 3, 13 => 6,
                          15 => 2, 16 => 1, 17 => 2, 18 => 2, 25 => 1, 27 => 2}.freeze

    # A two-arm condition is an `if`/`unless`/`&.` (then + else) or, rarely, a
    # `case` with a single `when`. These weights are the condition-type counts
    # restricted to two-arm conditions, and they reproduce the full type tally
    # exactly: `then` arms land at 31,737 (if + unless + `&.`) and `else` at
    # 32,750 (one per non-loop condition).
    TWO_ARM_CONDITION_TYPES = {if: 20_401, unless: 6123, "&.": 5213, case: 135}.freeze
    LOOP_CONDITION_TYPES = {while: 56, until: 14}.freeze
    # 33 of the 3,021 non-else `case` arms are pattern-matching `in` arms.
    PATTERN_MATCH_FRACTION = 0.011
    # Branch arms are almost never taken within a single shard.
    ZERO_HIT_ARM_FRACTION = 0.9922

    # Shards of the same suite share their file set, line shapes and branch
    # keys exactly; they differ only in hit counts, and only barely — 3,866 of
    # 591,499 lines between two adjacent shards.
    SHARD_DRIFT_FRACTION = 0.0065

    # Scaled headline targets the generated fixture is fitted to.
    def self.files(scale)
      (FILES / scale.to_f).round
    end

    def self.lines(scale)
      (LINES / scale.to_f).round
    end

    def self.conditions(scale)
      (CONDITIONS / scale.to_f).round
    end
  end
end
