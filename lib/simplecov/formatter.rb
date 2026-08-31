# frozen_string_literal: true

module SimpleCov
  module Formatter
    # Formatters are configured either as classes, instantiated fresh for every
    # report, or as ready-built instances, the only way to reach constructor
    # options like `HTMLFormatter.new(silent: true)` (#1240).
    def self.instance_for(formatter)
      instantiable?(formatter) ? formatter.new : formatter
    end

    # mutant:disable
    # `Class` cannot itself be subclassed, so `instance_of?(Class)` answers for
    # every object exactly as `is_a?(Class)` does: a difference no example can
    # show, which is why it is disabled here rather than pinned by a test.
    def self.instantiable?(formatter)
      formatter.is_a?(Class)
    end
    private_class_method :instantiable?

    def self.format(formatter, result)
      instance_for(formatter).format(result)
    end
  end
end

require_relative "formatter/simple_formatter"
require_relative "formatter/multi_formatter"
require_relative "formatter/json_formatter"
require_relative "formatter/baseline_formatter"
