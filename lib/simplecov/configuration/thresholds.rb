# frozen_string_literal: true

module SimpleCov
  # Coverage threshold configuration: `minimum_coverage`,
  # `maximum_coverage`, `expected_coverage`, `maximum_coverage_drop`,
  # `minimum_coverage_by_file`, `minimum_coverage_by_group`,
  # `refuse_coverage_drop`, and friends.
  module Configuration
    #
    # Defines the minimum overall coverage required for the testsuite to pass.
    # Returns non-zero if the current coverage is below this threshold.
    # Default is 0% (disabled).
    #
    def minimum_coverage(coverage = nil)
      return @minimum_coverage ||= {} unless coverage

      coverage = {primary_coverage => coverage} if coverage.is_a?(Numeric)
      raise_on_invalid_coverage(coverage, "minimum_coverage")
      @minimum_coverage = coverage
    end

    def raise_on_invalid_coverage(coverage, coverage_setting)
      coverage.each_key { |criterion| raise_if_criterion_disabled(criterion) }
      coverage.each_value do |percent|
        minimum_possible_coverage_exceeded(coverage_setting) if percent && percent > 100
      end
    end

    #
    # Defines the maximum overall coverage allowed for the testsuite to
    # pass. Useful paired with `minimum_coverage` (or via
    # `expected_coverage`) to pin coverage to an exact value, so an
    # unexpected jump up fails the build. See #187.
    #
    def maximum_coverage(coverage = nil)
      return @maximum_coverage ||= {} unless coverage

      coverage = {primary_coverage => coverage} if coverage.is_a?(Numeric)
      raise_on_invalid_coverage(coverage, "maximum_coverage")
      @maximum_coverage = coverage
    end

    #
    # Pins the suite to an exact coverage figure by setting both
    # `minimum_coverage` and `maximum_coverage`. See #187.
    #
    def expected_coverage(coverage = nil)
      return minimum_coverage if coverage.nil?

      minimum_coverage(coverage)
      maximum_coverage(coverage)
    end

    #
    # Defines the maximum coverage drop at once allowed for the
    # testsuite to pass. Default is 100% (disabled).
    #
    def maximum_coverage_drop(coverage_drop = nil)
      return @maximum_coverage_drop ||= {} unless coverage_drop

      coverage_drop = {primary_coverage => coverage_drop} if coverage_drop.is_a?(Numeric)
      raise_on_invalid_coverage(coverage_drop, "maximum_coverage_drop")
      @maximum_coverage_drop = coverage_drop
    end

    #
    # Defines the minimum coverage per file required for the testsuite
    # to pass. Accepts a Numeric (global threshold on the primary
    # criterion), a Symbol-keyed Hash (per-criterion globals), or a
    # Hash mixing Symbol keys with String / Regexp keys to declare
    # per-path overrides. See README and #575.
    #
    def minimum_coverage_by_file(coverage = nil)
      return @minimum_coverage_by_file ||= {} unless coverage

      coverage = {primary_coverage => coverage} if coverage.is_a?(Numeric)
      defaults, overrides = partition_per_file_thresholds(coverage)

      SimpleCov::Deprecation.warn("`SimpleCov.minimum_coverage_by_file` is deprecated. " \
                                  "Replace it with:\n#{per_file_coverage_replacement(defaults, overrides)}")

      raise_on_invalid_coverage(defaults, "minimum_coverage_by_file")
      overrides.each_value { |criteria| raise_on_invalid_coverage(criteria, "minimum_coverage_by_file") }

      @minimum_coverage_by_file = defaults
      @minimum_coverage_by_file_overrides = overrides
    end

    # Returns the per-path overrides set via `minimum_coverage_by_file`.
    def minimum_coverage_by_file_overrides
      @minimum_coverage_by_file_overrides ||= {}
    end

    #
    # Defines the minimum coverage per group required for the testsuite
    # to pass. Default is 0% (disabled).
    #
    def minimum_coverage_by_group(coverage = nil)
      return @minimum_coverage_by_group ||= {} unless coverage

      SimpleCov::Deprecation.warn("`SimpleCov.minimum_coverage_by_group` is deprecated. " \
                                  "Replace it with:\n#{per_group_coverage_replacement(coverage)}")
      @minimum_coverage_by_group = coverage.dup.transform_values do |group_coverage|
        group_coverage = {primary_coverage => group_coverage} if group_coverage.is_a?(Numeric)
        raise_on_invalid_coverage(group_coverage, "minimum_coverage_by_group")
        group_coverage
      end
    end

    #
    # Refuses any coverage drop. Coverage is only allowed to increase.
    #
    def refuse_coverage_drop(*criteria)
      criteria = coverage_criteria if criteria.empty?
      maximum_coverage_drop(criteria.to_h { |c| [c, 0] })
    end

  private

    # Split a `minimum_coverage_by_file` argument into Symbol-keyed
    # criterion defaults and String/Regexp-keyed per-path overrides;
    # normalize Numeric override values to `{primary_coverage => N}`
    # so downstream code only has one shape to handle.
    def partition_per_file_thresholds(coverage)
      coverage.each_key { |key| validate_per_file_key(key) }
      pairs = coverage.partition { |key, _| key.is_a?(Symbol) }
      # The assertions restate what the partition predicate guarantees:
      # Symbol keys carry per-criterion Numeric defaults, the rest are paths.
      defaults = pairs[0].to_h #: coverage_thresholds
      raw = pairs[1].to_h #: Hash[String | Regexp, Numeric | coverage_thresholds]
      overrides = raw.transform_values { |value| value.is_a?(Numeric) ? {primary_coverage => value} : value }
      [defaults, overrides]
    end

    def validate_per_file_key(key)
      return if key.is_a?(Symbol) || key.is_a?(String) || key.is_a?(Regexp)

      raise SimpleCov::ConfigurationError,
            "minimum_coverage_by_file keys must be Symbol (criterion), String, or Regexp; got #{key.inspect}"
    end

    def minimum_possible_coverage_exceeded(coverage_option)
      warn "The coverage you set for #{coverage_option} is greater than 100%"
    end

    # Render the `coverage` configuration equivalent to a (deprecated)
    # `minimum_coverage_by_file` argument so the deprecation warning can be
    # copy-pasted verbatim into the user's config.
    def per_file_coverage_replacement(defaults, overrides)
      by_criterion = {} #: Hash[Symbol, Array[String]]
      defaults.each { |criterion, percent| (by_criterion[criterion] ||= []) << "minimum_per_file #{percent}" }
      overrides.each do |target, criteria|
        criteria.each do |criterion, percent|
          (by_criterion[criterion] ||= []) << "minimum_per_file #{percent}, only: #{target.inspect}"
        end
      end
      render_coverage_blocks(by_criterion)
    end

    # Same, for a (deprecated) `minimum_coverage_by_group` argument.
    def per_group_coverage_replacement(coverage)
      by_criterion = {} #: Hash[Symbol, Array[String]]
      coverage.each do |group_name, thresholds|
        normalized = (thresholds.is_a?(Numeric) ? {primary_coverage => thresholds} : thresholds) #: coverage_thresholds
        normalized.each do |criterion, percent|
          (by_criterion[criterion] ||= []) << "minimum_per_group #{percent}, only: #{group_name.inspect}"
        end
      end
      render_coverage_blocks(by_criterion)
    end

    def render_coverage_blocks(by_criterion)
      by_criterion.map do |criterion, statements|
        "  coverage(#{criterion.inspect}) { #{statements.join('; ')} }"
      end.join("\n")
    end
  end
end
