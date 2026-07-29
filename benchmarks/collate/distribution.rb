# frozen_string_literal: true

module CollateBenchmark
  # Sampling helpers for turning the measured quantile curves in
  # `Shape` back into concrete per-file numbers.
  module Distribution
  module_function

    # Draw `count` values by walking the inverse CDF at evenly spaced
    # quantiles — no PRNG, so the distribution is reproduced rather than
    # sampled — then scale the result to sum to exactly `total`.
    def samples(curve, count, total:, floor:)
      raw = Array.new(count) { |index| interpolate(curve, (index + 0.5) / count) }
      fit_total(raw, total, floor)
    end

    # Scales `values` to sum to `total`. Scaling preserves the shape of the
    # distribution; the rounding residual is a handful of lines out of six
    # figures.
    def fit_total(values, total, floor)
      factor = total.to_f / values.sum
      scaled = values.map { |value| [(value * factor).round, floor].max }
      absorb_residual(scaled, total - scaled.sum, floor)
    end

    # Walks the largest entries by ±1 until the total is exact, skipping any
    # entry already at the floor so a downward correction can't produce a
    # zero-line file.
    def absorb_residual(scaled, residual, floor)
      return scaled if residual.zero?

      step = residual.positive? ? 1 : -1
      largest_first(scaled).cycle do |index|
        break if residual.zero?
        next if step.negative? && scaled[index] <= floor

        scaled[index] += step
        residual -= step
      end
      scaled
    end

    def largest_first(values)
      (0...values.size).sort_by { |index| -values[index] }
    end

    # Piecewise-linear inverse CDF over a {quantile => value} curve.
    def interpolate(curve, quantile)
      points = curve.to_a
      index = points.index { |point_quantile, _| point_quantile >= quantile } || (points.size - 1)
      return points[index].last if index.zero?

      lerp(points[index - 1], points[index], quantile)
    end

    def lerp(low, high, quantile)
      low_quantile, low_value = low
      high_quantile, high_value = high
      ratio = (quantile - low_quantile) / (high_quantile - low_quantile)
      (low_value + ((high_value - low_value) * ratio)).round
    end

    # Picks a key from a {value => weight} Hash. Weights are the observed
    # counts, so they need no normalizing.
    def weighted_choice(weights, rng)
      target = rng.rand * weights.values.sum
      running = 0.0
      weights.each do |value, weight|
        running += weight
        return value if running >= target
      end
      weights.keys.last
    end
  end
end
