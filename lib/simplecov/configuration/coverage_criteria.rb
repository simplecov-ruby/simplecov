# frozen_string_literal: true

module SimpleCov
  # Selection and validation of the coverage criteria Ruby's `Coverage`
  # library should track. Supports `:line` (the historical default),
  # `:branch`, `:method`, and `:oneshot_line`. The standalone `:eval`
  # toggle lives in `eval_coverage.rb`.
  module Configuration
    SUPPORTED_COVERAGE_CRITERIA = %i[line branch method oneshot_line].freeze
    DEFAULT_COVERAGE_CRITERION = :line
    ONESHOT_LINE_COVERAGE_CRITERION = :oneshot_line
    LINE_COVERAGE_ALTERNATIVES = {line: :oneshot_line, oneshot_line: :line}.freeze #: line_coverage_alternatives
    private_constant :LINE_COVERAGE_ALTERNATIVES

    # Enable one or more coverage criteria. `:eval` is accepted as a
    # shorthand for the standalone eval-coverage toggle.
    def enable_coverage(*criteria)
      criteria.each { |criterion| criterion == :eval ? enable_eval_coverage : add_coverage_criterion(criterion) }
    end

    # Remove `criterion` from the set of enabled coverage criteria.
    # `:eval` turns the standalone eval-coverage toggle back off,
    # mirroring `enable_coverage`. Disabling every criterion raises at
    # `start_tracking` (not here), so config files that toggle criteria
    # in arbitrary order don't have to worry about transient empty states.
    def disable_coverage(criterion)
      return disable_eval_coverage if criterion == :eval

      raise_if_criterion_unsupported(criterion)
      coverage_criteria.delete(criterion)
      @primary_coverage = nil if @primary_coverage == criterion
    end

    def primary_coverage(criterion = nil)
      if criterion.nil?
        @primary_coverage ||= default_primary_coverage
      else
        raise_if_criterion_disabled(criterion)
        @primary_coverage = criterion
      end
    end

    def coverage_criteria
      @coverage_criteria ||= Set[DEFAULT_COVERAGE_CRITERION]
    end

    def coverage_criterion_enabled?(criterion)
      coverage_criteria.member?(criterion)
    end

    # Reset the criteria back to the lazy default (`Set[:line]`).
    def clear_coverage_criteria
      @coverage_criteria = nil
      @primary_coverage = nil
    end

    # @api private — called from `SimpleCov.start_tracking` to fail
    # fast when the user has disabled every coverage criterion.
    def validate_coverage_criteria!
      return unless coverage_criteria.empty?

      raise SimpleCov::ConfigurationError,
            "At least one coverage criterion must be enabled. " \
            "Re-enable one with `enable_coverage :line`, `:branch`, or `:method`."
    end

    # Whether this run produces line data at all. The oneshot variant counts:
    # `ResultAdapter` turns its executed-line list back into a line array. A
    # branch-only or method-only run produces none, and `Coverage.result`
    # entries for the files it loaded carry no `"lines"` key.
    def line_coverage?
      coverage_criterion_enabled?(DEFAULT_COVERAGE_CRITERION) ||
        coverage_criterion_enabled?(ONESHOT_LINE_COVERAGE_CRITERION)
    end

    def branch_coverage?
      coverage_criterion_enabled?(:branch)
    end

    def method_coverage?
      coverage_criterion_enabled?(:method)
    end

  private

    def add_coverage_criterion(criterion)
      raise_if_criterion_unsupported(criterion)
      incompatible = LINE_COVERAGE_ALTERNATIVES[criterion]
      disable_coverage(incompatible) if incompatible
      coverage_criteria << criterion
    end

    # If `:line` is enabled, it's the default primary; otherwise fall
    # back to whichever criterion the user actually enabled (in
    # insertion order). Returning `:line` even when disabled would
    # propagate broken state into `minimum_coverage 90`.
    def default_primary_coverage
      return DEFAULT_COVERAGE_CRITERION if coverage_criterion_enabled?(DEFAULT_COVERAGE_CRITERION)

      # Set#first types as nilable, but an empty criteria set is rejected at
      # start_tracking before any caller can observe a nil here.
      _ = coverage_criteria.first
    end

    def raise_if_criterion_disabled(criterion)
      # `coverage :eval` by itself IS supported — it's a standalone
      # toggle, never in the enabled-criteria set — so the generic
      # "unsupported criterion" message below would mislead here.
      if criterion == :eval
        raise SimpleCov::ConfigurationError,
              "Coverage criterion :eval only toggles measuring eval'd code; " \
              "it cannot carry thresholds or serve as the primary criterion"
      end

      raise_if_criterion_unsupported(criterion)
      return if coverage_criterion_enabled?(criterion)

      raise SimpleCov::ConfigurationError,
            "Coverage criterion #{criterion}, is disabled! " \
            "Please enable it first through enable_coverage #{criterion} (if supported)"
    end

    def raise_if_criterion_unsupported(criterion)
      return if SUPPORTED_COVERAGE_CRITERIA.member?(criterion)

      raise SimpleCov::ConfigurationError,
            "Unsupported coverage criterion #{criterion}, supported values are #{SUPPORTED_COVERAGE_CRITERIA}"
    end
  end
end
