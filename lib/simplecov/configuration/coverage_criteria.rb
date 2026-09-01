# frozen_string_literal: true

module SimpleCov
  module Configuration
    SUPPORTED_COVERAGE_CRITERIA = %i[line branch method oneshot_line].freeze
    DEFAULT_COVERAGE_CRITERION = :line
    ONESHOT_LINE_COVERAGE_CRITERION = :oneshot_line
    LINE_COVERAGE_ALTERNATIVES = {line: :oneshot_line, oneshot_line: :line}.freeze #: line_coverage_alternatives
    private_constant :LINE_COVERAGE_ALTERNATIVES

    def enable_coverage(*criteria)
      criteria.each do |criterion|
        criterion.equal?(:eval) ? enable_eval_coverage : add_coverage_criterion(_ = criterion)
      end
    end

    # Disabling every criterion raises at `start_tracking`, not here, so config
    # files that toggle criteria in arbitrary order don't have to worry about
    # transient empty states.
    def disable_coverage(criterion)
      return disable_eval_coverage if criterion.equal?(:eval)

      raise_if_criterion_unsupported(_ = criterion)
      coverage_criteria.delete(_ = criterion)
      @primary_coverage = nil if @primary_coverage.equal?(criterion)
    end

    def primary_coverage(criterion = nil)
      if criterion.nil?
        @primary_coverage ||= default_primary_coverage
      else
        self.primary_coverage = criterion
      end
    end

    def primary_coverage=(criterion)
      raise_if_criterion_disabled(criterion)
      @primary_coverage = criterion
    end

    def coverage_criteria
      @coverage_criteria ||= Set[DEFAULT_COVERAGE_CRITERION]
    end

    def coverage_criterion_enabled?(criterion)
      coverage_criteria.member?(criterion)
    end

    def clear_coverage_criteria
      @coverage_criteria = nil
      @primary_coverage = nil
    end

    def validate_coverage_criteria!
      return unless coverage_criteria.empty?

      raise ConfigurationError,
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

    # Older Rubies don't expose `Coverage.supported?`, so fall back to the
    # historical engine check that line/branch/method were unavailable on JRuby.
    # `:eval` was added later, so its fallback is "always unsupported".
    def coverage_criterion_supported?(criterion)
      load_coverage
      return Coverage.supported?(criterion) if Coverage.respond_to?(:supported?)

      !criterion.eql?(:eval) && !RUBY_ENGINE.eql?("jruby")
    end

    # Loading `simplecov/configuration` on its own leaves Coverage undefined, and
    # this question is asked at configuration time.
    def load_coverage
      require "coverage"
    end

    private

    def add_coverage_criterion(criterion)
      raise_if_criterion_unsupported(criterion)
      incompatible = LINE_COVERAGE_ALTERNATIVES[criterion]
      disable_coverage(incompatible) if incompatible
      coverage_criteria << criterion
    end

    # Answering `:line` even when it is disabled would propagate broken state
    # into `minimum_coverage 90`, so fall back to whichever criterion the user
    # actually enabled, in insertion order.
    def default_primary_coverage
      return DEFAULT_COVERAGE_CRITERION if coverage_criterion_enabled?(DEFAULT_COVERAGE_CRITERION)

      _ = coverage_criteria.first
    end

    def raise_if_criterion_disabled(criterion)
      if criterion.equal?(:eval)
        raise ConfigurationError,
          "Coverage criterion :eval only toggles measuring eval'd code; " \
          "it cannot carry thresholds or serve as the primary criterion"
      end

      raise_if_criterion_unsupported(criterion)
      return if coverage_criterion_enabled?(criterion)

      raise ConfigurationError,
        "Coverage criterion #{criterion}, is disabled! " \
        "Please enable it first through enable_coverage #{criterion} (if supported)"
    end

    def raise_if_criterion_unsupported(criterion)
      return if SUPPORTED_COVERAGE_CRITERIA.member?(criterion)

      raise ConfigurationError,
        "Unsupported coverage criterion #{criterion}, supported values are #{SUPPORTED_COVERAGE_CRITERIA}"
    end
  end
end
