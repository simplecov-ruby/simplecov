# frozen_string_literal: true

module SimpleCov
  # The `coverage` configuration method configures each coverage criterion
  # (`:line`, `:branch`, `:method`, `:eval`) uniformly in one place: naming a
  # criterion enables it,
  # and every threshold is declared with the same syntax regardless of which
  # criterion it applies to. Because the criterion is fixed by the enclosing
  # `coverage` call, threshold values are always plain percentages — there is
  # no per-criterion Hash competing with the value for a slot.
  #
  #   SimpleCov.start do
  #     coverage :line do
  #       minimum          90
  #       minimum_per_file 80
  #       minimum_per_file 100, only: "app/mailers/request_mailer.rb"
  #       maximum_drop     5
  #     end
  #
  #     coverage :branch, minimum: 80
  #     coverage :method, minimum: 100
  #   end
  #
  # Line coverage is enabled by default, so `coverage :line` is only needed to
  # set line thresholds or options. Thresholds feed the same internal stores
  # as the flat `minimum_coverage` family, so enforcement is unchanged.
  module Configuration
    # One-liner keyword options `coverage` accepts, each forwarding to the
    # `CoverageCriterion` verb of the same name. `minimum_per_group` is omitted
    # because it needs an `only:` target, so it's block-only.
    COVERAGE_THRESHOLD_OPTIONS = %i[minimum maximum exact maximum_drop minimum_per_file].freeze

    #
    # Configure (and, unless `enabled: false`, enable) a coverage criterion.
    #
    # Threshold options mirror the block verbs for one-liner use:
    #   coverage :branch, minimum: 80, maximum_drop: 5
    #
    # `primary: true` makes this the report's leading criterion (and the one a
    # bare `minimum_coverage 90` targets). `oneshot: true` (valid only for
    # `:line`) selects the faster oneshot-lines mode. `:eval` is enable-only.
    #
    def coverage(criterion, primary: false, enabled: true, oneshot: false, **thresholds, &block)
      criterion = enable_coverage_criterion(criterion, enabled: enabled, oneshot: oneshot)
      primary_coverage(criterion) if primary

      configurator = CoverageCriterion.new(self, criterion)
      apply_threshold_options(configurator, thresholds)
      configurator.instance_eval(&block) if block

      criterion
    end

  private

    # Forward the one-liner threshold keywords (`coverage :branch, minimum: 80`)
    # to the matching `CoverageCriterion` verbs, rejecting anything that isn't a
    # recognized threshold option.
    def apply_threshold_options(configurator, options)
      options.each do |verb, value|
        unless COVERAGE_THRESHOLD_OPTIONS.include?(verb)
          raise SimpleCov::ConfigurationError,
                "Unknown `coverage` option #{verb.inspect}. " \
                "Supported options are #{COVERAGE_THRESHOLD_OPTIONS.inspect}."
        end

        configurator.public_send(verb, value)
      end
    end

    # Enable the criterion (or its oneshot / eval variant) and return the
    # criterion symbol that thresholds should be stored under.
    def enable_coverage_criterion(criterion, enabled:, oneshot:)
      return enable_oneshot_line(criterion) if oneshot
      return enable_eval_coverage_criterion if criterion == :eval

      enabled ? enable_coverage(criterion) : disable_coverage(criterion)
      criterion
    end

    def enable_oneshot_line(criterion)
      unless criterion == :line
        raise SimpleCov::ConfigurationError, "`oneshot: true` is only valid for `coverage :line`"
      end

      enable_coverage(ONESHOT_LINE_COVERAGE_CRITERION)
      ONESHOT_LINE_COVERAGE_CRITERION
    end

    def enable_eval_coverage_criterion
      enable_coverage(:eval)
      :eval
    end

    # @api private — threshold-store writers used by CoverageCriterion. They
    # write the same `@minimum_coverage` / `@maximum_coverage` / ... hashes the
    # flat threshold methods populate, so the exit-code checks are unchanged.
    def store_overall_threshold(setting, criterion, percent)
      raise_on_invalid_coverage({criterion => percent}, setting.to_s)
      public_send(setting)[criterion] = percent
    end

    def store_minimum_per_file(criterion, percent, target)
      raise_on_invalid_coverage({criterion => percent}, "minimum_coverage_by_file")
      return minimum_coverage_by_file[criterion] = percent if target.nil?

      unless target.is_a?(String) || target.is_a?(Regexp)
        raise SimpleCov::ConfigurationError, "`only:` must be a String path or Regexp, got #{target.inspect}"
      end

      (minimum_coverage_by_file_overrides[target] ||= {})[criterion] = percent
    end

    def store_minimum_per_group(criterion, percent, group_name)
      raise_on_invalid_coverage({criterion => percent}, "minimum_coverage_by_group")
      (minimum_coverage_by_group[group_name] ||= {})[criterion] = percent
    end

    #
    # Receiver for a `coverage <criterion> do ... end` block. Each verb writes a
    # threshold for the single criterion the block configures, so the value is
    # always a plain percentage (`minimum_per_file 100` is unambiguous) and the
    # syntax is identical across line, branch, and method coverage.
    #
    class CoverageCriterion
      def initialize(config, criterion)
        @config = config
        @criterion = criterion
      end

      # Overall (suite-wide) minimum for this criterion.
      def minimum(percent)
        @config.send(:store_overall_threshold, :minimum_coverage, @criterion, percent)
      end

      # Overall maximum: fails the build if coverage rises above it. Paired with
      # `minimum` (or via `exact`) this pins coverage so an unexpected jump fails.
      def maximum(percent)
        @config.send(:store_overall_threshold, :maximum_coverage, @criterion, percent)
      end

      # Pin coverage to an exact figure (sets both `minimum` and `maximum`).
      def exact(percent)
        minimum(percent)
        maximum(percent)
      end

      # Maximum allowed drop between runs (`maximum_drop 0` refuses any drop).
      def maximum_drop(percent)
        @config.send(:store_overall_threshold, :maximum_coverage_drop, @criterion, percent)
      end

      # Per-file minimum. With no `only:`, sets the default applied to every
      # file; with `only:` (a String path or Regexp), overrides that default
      # for the matching files.
      def minimum_per_file(percent, only: nil)
        @config.send(:store_minimum_per_file, @criterion, percent, only)
      end

      # Per-group minimum for the named group (defined via `group`).
      def minimum_per_group(percent, only:)
        @config.send(:store_minimum_per_group, @criterion, percent, only)
      end

      # Make this criterion the report's primary (leading) criterion.
      def primary
        @config.primary_coverage(@criterion)
      end
    end
  end
end
