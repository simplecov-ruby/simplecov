# frozen_string_literal: true

module SimpleCov
  module Configuration
    def minimum_coverage(coverage = nil)
      return @minimum_coverage ||= {} unless coverage

      @minimum_coverage = normalized_threshold(coverage, "minimum_coverage")
    end

    def raise_on_invalid_coverage(coverage, coverage_setting)
      coverage.each_key { |criterion| raise_if_criterion_disabled(criterion) }
      coverage.each_value do |percent|
        minimum_possible_coverage_exceeded(coverage_setting) if percent && percent > 100
      end
    end

    #
    # The maximum overall coverage allowed for the testsuite to pass. Useful
    # paired with `minimum_coverage` (or via `expected_coverage`) to pin
    # coverage to an exact value, so an unexpected jump up fails the build
    # (#187).
    #
    def maximum_coverage(coverage = nil)
      return @maximum_coverage ||= {} unless coverage

      @maximum_coverage = normalized_threshold(coverage, "maximum_coverage")
    end

    def expected_coverage(coverage = nil)
      return minimum_coverage if coverage.nil?

      minimum_coverage(coverage)
      maximum_coverage(coverage)
    end

    def maximum_coverage_drop(coverage_drop = nil)
      return @maximum_coverage_drop ||= {} unless coverage_drop

      @maximum_coverage_drop = normalized_threshold(coverage_drop, "maximum_coverage_drop")
    end

    #
    # The minimum coverage per file required for the testsuite to pass.
    # Accepts a Numeric (global threshold on the primary criterion), a
    # Symbol-keyed Hash (per-criterion globals), or a Hash mixing Symbol keys
    # with String / Regexp keys to declare per-path overrides (#575).
    #
    def minimum_coverage_by_file(coverage = nil)
      return @minimum_coverage_by_file ||= {} unless coverage

      coverage = {primary_coverage => coverage} if coverage.is_a?(Numeric)
      defaults, overrides = partition_per_file_thresholds(coverage)

      Deprecation.warn("`SimpleCov.minimum_coverage_by_file` is deprecated. " \
                       "Replace it with:\n#{per_file_coverage_replacement(defaults, overrides)}")

      raise_on_invalid_coverage(defaults, "minimum_coverage_by_file")
      overrides.each_value { |criteria| raise_on_invalid_coverage(criteria, "minimum_coverage_by_file") }

      @minimum_coverage_by_file = defaults
      @minimum_coverage_by_file_overrides = overrides
    end

    def minimum_coverage_by_file_overrides
      @minimum_coverage_by_file_overrides ||= {}
    end

    def minimum_coverage_by_group(coverage = nil)
      return @minimum_coverage_by_group ||= {} unless coverage

      Deprecation.warn("`SimpleCov.minimum_coverage_by_group` is deprecated. " \
                       "Replace it with:\n#{per_group_coverage_replacement(coverage)}")
      @minimum_coverage_by_group = coverage.to_h do |group_name, group_coverage|
        [GroupNames.normalize(group_name), normalized_threshold(group_coverage, "minimum_coverage_by_group")]
      end
    end

    def refuse_coverage_drop(*criteria)
      criteria = coverage_criteria if criteria.empty?
      maximum_coverage_drop(criteria.to_h { |c| [c, 0] })
    end

    private

    # A bare Numeric targets the primary criterion, and the resulting
    # per-criterion hash is validated before it is stored.
    def normalized_threshold(coverage, setting)
      coverage = {primary_coverage => coverage} if coverage.is_a?(Numeric)
      coverage.tap { |thresholds| raise_on_invalid_coverage(thresholds, setting) }
    end

    # Splits into Symbol-keyed criterion defaults and String/Regexp-keyed
    # per-path overrides, normalizing Numeric override values to
    # `{primary_coverage => N}` so downstream code has one shape to handle.
    def partition_per_file_thresholds(coverage)
      coverage.each_key { |key| validate_per_file_key(key) }
      # The assertions restate what the partition predicate guarantees: Symbol
      # keys carry per-criterion Numeric defaults, the rest are paths.
      symbol_pairs, path_pairs = coverage.partition { |key, _| key.instance_of?(Symbol) }
      defaults = symbol_pairs.to_h #: coverage_thresholds
      raw = path_pairs.to_h #: Hash[String | Regexp, Numeric | coverage_thresholds]
      overrides = raw.transform_values { |value| value.is_a?(Numeric) ? {primary_coverage => value} : value }
      [defaults, overrides]
    end

    def validate_per_file_key(key)
      # Symbols have no subclasses; paths and patterns may.
      return if key.instance_of?(Symbol) || key.is_a?(String) || key.is_a?(Regexp)

      raise ConfigurationError,
        "minimum_coverage_by_file keys must be Symbol (criterion), String, or Regexp; got #{key.inspect}"
    end

    def minimum_possible_coverage_exceeded(coverage_option)
      warn "The coverage you set for #{coverage_option} is greater than 100%"
    end

    # Renders the `coverage` configuration equivalent to a deprecated
    # `minimum_coverage_by_file` argument, so the deprecation warning can be
    # copy-pasted verbatim into the user's config.
    def per_file_coverage_replacement(defaults, overrides)
      by_criterion = {} #: Hash[Symbol, Array[String]]
      defaults.each { |criterion, percent| (by_criterion[criterion] ||= []) << "minimum #{percent}, per: :file" }
      overrides.each do |target, criteria|
        criteria.each do |criterion, percent|
          (by_criterion[criterion] ||= []) << "minimum #{percent}, per: #{target.inspect}"
        end
      end
      render_coverage_blocks(by_criterion)
    end

    def per_group_coverage_replacement(coverage)
      by_criterion = {} #: Hash[Symbol, Array[String]]
      coverage.each do |group_name, thresholds|
        normalized = (thresholds.is_a?(Numeric) ? {primary_coverage => thresholds} : thresholds) #: coverage_thresholds
        normalized.each do |criterion, percent|
          (by_criterion[criterion] ||= []) << "minimum #{percent}, per: group(#{group_name.inspect})"
        end
      end
      render_coverage_blocks(by_criterion)
    end

    def render_coverage_blocks(by_criterion)
      by_criterion.map do |criterion, statements|
        "  coverage(#{criterion.inspect}) { #{statements.join("; ")} }"
      end.join("\n")
    end
  end
end
