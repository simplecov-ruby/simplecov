# frozen_string_literal: true

module SimpleCov
  module Configuration
    # Caps the total number of misses per criterion. Where a percent minimum
    # asks for a ratio, this asks for an absolute burn-down number, which stays
    # meaningful as the codebase grows and shrinks.
    def maximum_missed(counts = nil)
      return @maximum_missed ||= {} unless counts

      @maximum_missed = normalized_missed_caps(counts, "maximum_missed")
    end

    # Unlike a percent minimum, which systematically flatters big files, this
    # holds every file to the same absolute budget. Files with a baseline entry
    # are exempt per covered criterion, as they are from the per-file minimum.
    def maximum_missed_per_file(counts = nil)
      return @maximum_missed_per_file ||= {} unless counts

      Deprecation.warn("`SimpleCov.maximum_missed_per_file` is deprecated. " \
                       "Replace it with:\n#{missed_per_file_replacement(counts)}")
      @maximum_missed_per_file = normalized_missed_caps(counts, "maximum_missed_per_file")
    end

    def maximum_missed_per_file_overrides
      @maximum_missed_per_file_overrides ||= {}
    end

    private

    def normalized_missed_caps(counts, setting)
      counts = {primary_coverage => counts} if counts.is_a?(Numeric)
      counts.each_key { |criterion| raise_if_criterion_disabled(criterion) }
      counts.each_value { |cap| raise_on_invalid_missed_cap(cap, setting) }
      _ = counts
    end

    def raise_on_invalid_missed_cap(cap, setting)
      return if cap.instance_of?(Integer) && cap >= 0

      raise ConfigurationError,
        "#{setting} takes a non-negative integer count of misses, got #{cap.inspect}"
    end

    def missed_per_file_replacement(counts)
      counts = {primary_coverage => counts} if counts.is_a?(Numeric)
      counts.map { |criterion, cap| "  coverage(#{criterion.inspect}) { maximum_missed #{cap}, per: :file }" }
        .join("\n")
    end
  end
end
