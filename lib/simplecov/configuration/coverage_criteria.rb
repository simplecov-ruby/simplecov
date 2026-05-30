# frozen_string_literal: true

module SimpleCov
  # Selection and validation of the coverage criteria Ruby's `Coverage`
  # library should track. Supports `:line` (the historical default),
  # `:branch`, `:method`, and `:oneshot_line`, plus the standalone
  # `:eval` toggle for instrumenting `eval`'d code.
  module Configuration
    SUPPORTED_COVERAGE_CRITERIA = %i[line branch method oneshot_line].freeze
    DEFAULT_COVERAGE_CRITERION = :line
    ONESHOT_LINE_COVERAGE_CRITERION = :oneshot_line

    # Enable one or more coverage criteria. `:eval` is accepted as a
    # shorthand for the standalone eval-coverage toggle.
    def enable_coverage(*criteria)
      criteria.each do |criterion|
        if criterion == :eval
          enable_eval_coverage
        else
          raise_if_criterion_unsupported(criterion)
          # :oneshot_lines can not be combined with :lines
          coverage_criteria.delete(DEFAULT_COVERAGE_CRITERION) if criterion == ONESHOT_LINE_COVERAGE_CRITERION
          coverage_criteria << criterion
        end
      end
    end

    # Remove `criterion` from the set of enabled coverage criteria.
    # Disabling every criterion raises at `start_tracking` (not here),
    # so config files that toggle criteria in arbitrary order don't
    # have to worry about transient empty states.
    def disable_coverage(criterion)
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

    def branch_coverage?
      branch_coverage_supported? && coverage_criterion_enabled?(:branch)
    end

    def branch_coverage_supported?
      coverage_criterion_supported?(:branches)
    end

    def method_coverage?
      method_coverage_supported? && coverage_criterion_enabled?(:method)
    end

    def method_coverage_supported?
      coverage_criterion_supported?(:methods)
    end

    def coverage_for_eval_supported?
      coverage_criterion_supported?(:eval)
    end

    # Ask the Coverage runtime itself whether a criterion is supported
    # (Ruby >= 3.2). Older Rubies don't expose `Coverage.supported?`, so
    # fall back to the historical engine check that line/branch/method
    # were unavailable on JRuby. `:eval` was added later, so on older
    # Rubies its fallback is "always unsupported" rather than the
    # JRuby-only one above. The fallback arm is unreachable from the
    # dogfood report, which runs on a newer Ruby.
    # simplecov:disable
    def coverage_criterion_supported?(criterion)
      require "coverage"
      return Coverage.supported?(criterion) if Coverage.respond_to?(:supported?)

      criterion != :eval && RUBY_ENGINE != "jruby"
    end
    # simplecov:enable

    def coverage_for_eval_enabled?
      @coverage_for_eval_enabled ||= false
    end

    # DEPRECATED: prefer `enable_coverage :eval`.
    def enable_coverage_for_eval
      warn "#{Kernel.caller.first}: [DEPRECATION] `SimpleCov.enable_coverage_for_eval` is deprecated. " \
           "Replace with `SimpleCov.enable_coverage :eval`."
      enable_eval_coverage
    end

  private

    # Shared implementation backing both `enable_coverage :eval` and
    # the deprecated `enable_coverage_for_eval`.
    def enable_eval_coverage
      if coverage_for_eval_supported?
        @coverage_for_eval_enabled = true
      else
        warn "Coverage for eval is not available; Use Ruby 3.2.0 or later"
      end
    end

    # If `:line` is enabled, it's the default primary; otherwise fall
    # back to whichever criterion the user actually enabled (in
    # insertion order). Returning `:line` even when disabled would
    # propagate broken state into `minimum_coverage 90`.
    def default_primary_coverage
      return DEFAULT_COVERAGE_CRITERION if coverage_criterion_enabled?(DEFAULT_COVERAGE_CRITERION)

      coverage_criteria.first
    end

    def raise_if_criterion_disabled(criterion)
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
