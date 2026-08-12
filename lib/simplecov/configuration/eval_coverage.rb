# frozen_string_literal: true

module SimpleCov
  # The standalone eval-coverage toggle (`enable_coverage :eval`),
  # instrumenting `eval`'d code on Rubies that support it. Kept separate
  # from the criteria-set logic in `coverage_criteria.rb` because `:eval`
  # is a boolean toggle, never a member of the enabled-criteria set.
  module Configuration
    def coverage_for_eval_supported?
      coverage_criterion_supported?(:eval)
    end

    def coverage_for_eval_enabled?
      @coverage_for_eval_enabled ||= false
    end

  private

    # Implementation backing `enable_coverage :eval`.
    def enable_eval_coverage
      if coverage_for_eval_supported?
        @coverage_for_eval_enabled = true
      else
        warn "Coverage for eval is not available; Use Ruby 3.2.0 or later"
      end
    end

    # No support check needed: off is a safe state on every Ruby.
    def disable_eval_coverage
      @coverage_for_eval_enabled = false
    end
  end
end
