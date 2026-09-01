# frozen_string_literal: true

module SimpleCov
  module Configuration
    COVERAGE_THRESHOLD_OPTIONS = %i[minimum maximum exact maximum_drop ignore minimum_per_file
      maximum_missed maximum_missed_per_file].freeze

    def coverage(criterion, primary: false, enabled: true, oneshot: false, **thresholds, &block)
      criterion = enable_coverage_criterion(criterion, enabled: enabled, oneshot: oneshot)
      # The cast admits :eval, which primary_coverage rejects at runtime.
      primary_coverage(_ = criterion) if primary

      configurator = CoverageCriterion.new(self, criterion)
      apply_threshold_options(configurator, thresholds)
      configurator.instance_eval(&block) if block

      criterion
    end

    private

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

    # @api private
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
      # Normalized like `group` does, so `per: group(:Models)` finds the group
      # defined as `group "Models"` at check time.
      (minimum_coverage_by_group[GroupNames.normalize(group_name)] ||= {})[criterion] = percent
    end

    #
    # Receiver for a `coverage <criterion> do ... end` block.
    #
    class CoverageCriterion
      def initialize(config, criterion)
        @config = config
        @criterion = criterion
      end

      def minimum(percent, per: nil)
        case per
        when nil then @config.__send__(:store_overall_threshold, :minimum_coverage, @criterion, percent)
        when :file then @config.__send__(:store_minimum_per_file, @criterion, percent, nil)
        when String, Regexp then @config.__send__(:store_minimum_per_file, @criterion, percent, per)
        when GroupTarget then @config.__send__(:store_minimum_per_group, @criterion, percent, per.name)
        else raise_invalid_per(per)
        end
      end

      def maximum(percent)
        @config.__send__(:store_overall_threshold, :maximum_coverage, @criterion, percent)
      end

      def exact(percent)
        minimum(percent)
        maximum(percent)
      end

      def maximum_drop(percent)
        @config.__send__(:store_overall_threshold, :maximum_coverage_drop, @criterion, percent)
      end

      def maximum_missed(count, per: nil)
        case per
        when nil then @config.__send__(:store_missed_cap, :maximum_missed, @criterion, count)
        when :file then @config.__send__(:store_maximum_missed_per_file, @criterion, count, nil)
        when String, Regexp then @config.__send__(:store_maximum_missed_per_file, @criterion, count, per)
        when GroupTarget
          raise ConfigurationError,
            "maximum_missed does not support `per: group(...)` yet; see docs/Roadmap.md"
        else raise_invalid_per(per)
        end
      end

      def group(name)
        GroupTarget.new(name: name)
      end

      # The flatten serves the one-liner keyword form, whose value arrives as a
      # single argument (`ignore: %i[implicit_else]`).
      def ignore(*types)
        case @criterion
        when :branch then @config.__send__(:store_ignored_branches, types.flatten)
        when :method then @config.__send__(:store_ignored_methods, types.flatten)
        else
          raise ConfigurationError,
            "`ignore` is supported for `coverage :branch` and `coverage :method`, not #{@criterion.inspect}"
        end
      end

      def minimum_per_file(percent, only: nil)
        Deprecation.warn("`minimum_per_file` is deprecated. " \
                         "Replace with `minimum #{percent}, per: #{(only || :file).inspect}`.")
        @config.__send__(:store_minimum_per_file, @criterion, percent, only)
      end

      def minimum_per_group(percent, only:)
        Deprecation.warn("`minimum_per_group` is deprecated. " \
                         "Replace with `minimum #{percent}, per: group(#{only.inspect})`.")
        @config.__send__(:store_minimum_per_group, @criterion, percent, only)
      end

      def maximum_missed_per_file(count, only: nil)
        Deprecation.warn("`maximum_missed_per_file` is deprecated. " \
                         "Replace with `maximum_missed #{count}, per: #{(only || :file).inspect}`.")
        @config.__send__(:store_maximum_missed_per_file, @criterion, count, only)
      end

      def primary
        # @criterion is Symbol-wide because this receiver is also built for
        # :eval; primary_coverage validates at runtime.
        @config.primary_coverage(_ = @criterion)
      end

      GroupTarget = Data.define(:name)

      private

      def raise_invalid_per(per)
        raise ConfigurationError,
          "`per:` must be :file, a String path, a Regexp, or group(\"Name\"), got #{per.inspect}"
      end
    end
  end
end
