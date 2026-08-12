# frozen_string_literal: true

module SimpleCov
  # Coverage threshold configuration: `minimum_coverage`,
  # `maximum_coverage`, `expected_coverage`, `maximum_coverage_drop`,
  # `refuse_coverage_drop`, and the per-file / per-group threshold stores
  # the `coverage` block writes into.
  module Configuration
    #
    # Defines the minimum overall coverage required for the testsuite to pass.
    # Returns non-zero if the current coverage is below this threshold.
    # Default is 0% (disabled).
    #
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
    # Defines the maximum overall coverage allowed for the testsuite to
    # pass. Useful paired with `minimum_coverage` (or via
    # `expected_coverage`) to pin coverage to an exact value, so an
    # unexpected jump up fails the build. See #187.
    #
    def maximum_coverage(coverage = nil)
      return @maximum_coverage ||= {} unless coverage

      @maximum_coverage = normalized_threshold(coverage, "maximum_coverage")
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

      @maximum_coverage_drop = normalized_threshold(coverage_drop, "maximum_coverage_drop")
    end

    # @api private — per-criterion per-file minimums, written by the
    # `coverage` block's `minimum_per_file` verb and read by the checks.
    def minimum_coverage_by_file
      @minimum_coverage_by_file ||= {}
    end

    # @api private — per-path overrides set via `minimum_per_file only:`.
    def minimum_coverage_by_file_overrides
      @minimum_coverage_by_file_overrides ||= {}
    end

    # @api private — per-group minimums, written by the `coverage` block's
    # `minimum_per_group` verb and read by the checks.
    def minimum_coverage_by_group
      @minimum_coverage_by_group ||= {}
    end

    #
    # Refuses any coverage drop. Coverage is only allowed to increase.
    #
    def refuse_coverage_drop(*criteria)
      criteria = coverage_criteria if criteria.empty?
      maximum_coverage_drop(criteria.to_h { |c| [c, 0] })
    end

  private

    # Shared normalize-and-validate step behind every threshold setter:
    # a bare Numeric targets the primary criterion, and the resulting
    # per-criterion hash is validated before it is stored.
    def normalized_threshold(coverage, setting)
      coverage = {primary_coverage => coverage} if coverage.is_a?(Numeric)
      raise_on_invalid_coverage(coverage, setting)
      coverage
    end

    def minimum_possible_coverage_exceeded(coverage_option)
      warn "The coverage you set for #{coverage_option} is greater than 100%"
    end
  end
end
