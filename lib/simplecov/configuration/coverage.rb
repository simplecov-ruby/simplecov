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
  #       minimum 90
  #       minimum 80,  per: :file
  #       minimum 100, per: "app/mailers/request_mailer.rb"
  #       minimum 95,  per: group("Models")
  #       maximum_drop 5
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
    # `CoverageCriterion` verb of the same name. Scoped thresholds are
    # block-only, since a keyword slot carries the value and nothing
    # else; the deprecated `_per_file` names stay accepted for
    # configurations written before the `per:` axis existed.
    COVERAGE_THRESHOLD_OPTIONS = %i[minimum maximum exact maximum_drop ignore minimum_per_file
                                    maximum_missed maximum_missed_per_file].freeze

    #
    # Configure (and, unless `enabled: false`, enable) a coverage criterion.
    #
    # Threshold options mirror the block verbs for one-liner use:
    #   coverage :branch, minimum: 80, maximum_drop: 5
    #
    # `primary: true` makes this the report's leading criterion (and the one a
    # bare `minimum_coverage 90` targets). `oneshot: true` (valid only for
    # `:line`) selects the faster oneshot-lines mode.
    #
    def coverage(criterion, primary: false, enabled: true, oneshot: false, **thresholds, &block)
      criterion = enable_coverage_criterion(criterion, enabled: enabled, oneshot: oneshot)
      # The cast admits :eval, which primary_coverage rejects at runtime
      # (it is a standalone toggle, never in the enabled-criteria set).
      primary_coverage(_ = criterion) if primary

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
          raise ConfigurationError,
                "Unknown `coverage` option #{verb.inspect}. " \
                "Supported options are #{COVERAGE_THRESHOLD_OPTIONS.inspect}."
        end

        configurator.public_send(verb, value)
      end
    end

    # Enable or disable the criterion (or its oneshot / eval variant) and
    # return the criterion symbol that thresholds should be stored under.
    def enable_coverage_criterion(criterion, enabled:, oneshot:)
      criterion = resolve_criterion_variant(criterion, oneshot)
      enabled ? enable_coverage(criterion) : disable_coverage(criterion)
      criterion
    end

    def resolve_criterion_variant(criterion, oneshot)
      return criterion unless oneshot

      raise ConfigurationError, "`oneshot: true` is only valid for `coverage :line`" unless criterion.equal?(:line)

      ONESHOT_LINE_COVERAGE_CRITERION
    end

    # @api private — threshold-store writers used by CoverageCriterion. They
    # write the same `@minimum_coverage` / `@maximum_coverage` / ... hashes the
    # flat threshold methods populate, so the exit-code checks are unchanged.
    def store_overall_threshold(setting, criterion, percent)
      raise_on_invalid_coverage({criterion => percent}, setting)
      public_send(setting)[criterion] = percent
    end

    def store_missed_cap(setting, criterion, count)
      raise_if_criterion_disabled(criterion)
      raise_on_invalid_missed_cap(count, setting)
      public_send(setting)[criterion] = count
    end

    def store_maximum_missed_per_file(criterion, count, target)
      raise_if_criterion_disabled(criterion)
      raise_on_invalid_missed_cap(count, "maximum_missed_per_file")
      return maximum_missed_per_file[criterion] = count if target.nil?

      unless target.is_a?(String) || target.is_a?(Regexp)
        raise ConfigurationError, "`only:` must be a String path or Regexp, got #{target.inspect}"
      end

      (maximum_missed_per_file_overrides[target] ||= {})[criterion] = count
    end

    def store_minimum_per_file(criterion, percent, target)
      raise_on_invalid_coverage({criterion => percent}, "minimum_coverage_by_file")
      return minimum_coverage_by_file[criterion] = percent if target.nil?

      unless target.is_a?(String) || target.is_a?(Regexp)
        raise ConfigurationError, "`only:` must be a String path or Regexp, got #{target.inspect}"
      end

      (minimum_coverage_by_file_overrides[target] ||= {})[criterion] = percent
    end

    def store_minimum_per_group(criterion, percent, group_name)
      raise_on_invalid_coverage({criterion => percent}, "minimum_coverage_by_group")
      # Normalize like `group` does, so `only: :Models` finds the group
      # defined as `group "Models"` at check time instead of storing a
      # Symbol key no lookup ever matches.
      (minimum_coverage_by_group[GroupNames.normalize(group_name)] ||= {})[criterion] = percent
    end

    #
    # Receiver for a `coverage <criterion> do ... end` block. Each verb writes a
    # threshold for the single criterion the block configures, so the value is
    # always a plain number, the scope is a uniform `per:` argument, and the
    # syntax is identical across line, branch, and method coverage.
    #
    class CoverageCriterion
      def initialize(config, criterion)
        @config = config
        @criterion = criterion
      end

      # Minimum for this criterion. `per:` scopes it: nil (the default)
      # is the suite-wide minimum, `:file` the default applied to every
      # file, a String path or Regexp an override for the matching
      # files, and `group("Name")` the minimum for a named group.
      #
      #   minimum 90
      #   minimum 80,  per: :file
      #   minimum 100, per: "app/mailers/request_mailer.rb"
      #   minimum 95,  per: group("Models")
      def minimum(percent, per: nil)
        case per
        when nil                then @config.__send__(:store_overall_threshold, :minimum_coverage, @criterion, percent)
        when :file              then @config.__send__(:store_minimum_per_file, @criterion, percent, nil)
        when String, Regexp     then @config.__send__(:store_minimum_per_file, @criterion, percent, per)
        when GroupTarget        then @config.__send__(:store_minimum_per_group, @criterion, percent, per.name)
        else raise_invalid_per(per)
        end
      end

      # Overall maximum: fails the build if coverage rises above it. Paired with
      # `minimum` (or via `exact`) this pins coverage so an unexpected jump fails.
      def maximum(percent)
        @config.__send__(:store_overall_threshold, :maximum_coverage, @criterion, percent)
      end

      # Pin coverage to an exact figure (sets both `minimum` and `maximum`).
      def exact(percent)
        minimum(percent)
        maximum(percent)
      end

      # Maximum allowed drop between runs (`maximum_drop 0` refuses any drop).
      def maximum_drop(percent)
        @config.__send__(:store_overall_threshold, :maximum_coverage_drop, @criterion, percent)
      end

      # Cap on the number of misses (uncovered lines, branch arms, or
      # methods, depending on the block's criterion): an absolute
      # burn-down number rather than a ratio. `per:` scopes it the same
      # way `minimum`'s does, except that group targets are not
      # enforced yet (see docs/Roadmap.md).
      #
      #   maximum_missed 12
      #   maximum_missed 5, per: :file
      #   maximum_missed 0, per: "lib/critical.rb"
      def maximum_missed(count, per: nil)
        case per
        when nil                then @config.__send__(:store_missed_cap, :maximum_missed, @criterion, count)
        when :file              then @config.__send__(:store_maximum_missed_per_file, @criterion, count, nil)
        when String, Regexp     then @config.__send__(:store_maximum_missed_per_file, @criterion, count, per)
        when GroupTarget
          raise ConfigurationError,
                "maximum_missed does not support `per: group(...)` yet; see docs/Roadmap.md"
        else raise_invalid_per(per)
        end
      end

      # The `per:` target naming a group, distinguishing it from a
      # String path: `minimum 95, per: group("Models")`.
      def group(name)
        GroupTarget.new(name: name)
      end

      # Drop synthetic coverage entries of the given types for this
      # criterion: `coverage(:branch) { ignore :implicit_else, :eval_generated }`,
      # `coverage(:method) { ignore :eval_generated }`. Only branch and
      # method entries have ignorable types; line coverage has none.
      # The Array flatten serves the one-liner keyword form, whose value
      # arrives as a single argument (`ignore: %i[implicit_else]`).
      def ignore(*types)
        case @criterion
        when :branch then @config.__send__(:store_ignored_branches, types.flatten)
        when :method then @config.__send__(:store_ignored_methods, types.flatten)
        else
          raise ConfigurationError,
                "`ignore` is supported for `coverage :branch` and `coverage :method`, not #{@criterion.inspect}"
        end
      end

      # DEPRECATED: use `minimum N, per: :file` (or `per: "path"` /
      # `per: %r{regexp}` for an override).
      def minimum_per_file(percent, only: nil)
        Deprecation.warn("`minimum_per_file` is deprecated. " \
                         "Replace with `minimum #{percent}, per: #{(only || :file).inspect}`.")
        @config.__send__(:store_minimum_per_file, @criterion, percent, only)
      end

      # DEPRECATED: use `minimum N, per: group("Name")`.
      def minimum_per_group(percent, only:)
        Deprecation.warn("`minimum_per_group` is deprecated. " \
                         "Replace with `minimum #{percent}, per: group(#{only.inspect})`.")
        @config.__send__(:store_minimum_per_group, @criterion, percent, only)
      end

      # DEPRECATED: use `maximum_missed N, per: :file` (or `per: "path"`).
      def maximum_missed_per_file(count, only: nil)
        Deprecation.warn("`maximum_missed_per_file` is deprecated. " \
                         "Replace with `maximum_missed #{count}, per: #{(only || :file).inspect}`.")
        @config.__send__(:store_maximum_missed_per_file, @criterion, count, only)
      end

      # Make this criterion the report's primary (leading) criterion.
      def primary
        # @criterion is Symbol-wide because this receiver is also built for
        # :eval; primary_coverage validates at runtime.
        @config.primary_coverage(_ = @criterion)
      end

      # What `group("Name")` builds: a wrapper that keeps a group name
      # distinguishable from a String path in a `per:` argument.
      GroupTarget = Data.define(:name)

    private

      def raise_invalid_per(per)
        raise ConfigurationError,
              "`per:` must be :file, a String path, a Regexp, or group(\"Name\"), got #{per.inspect}"
      end
    end
  end
end
