# frozen_string_literal: true

module SimpleCov
  # Namespace for SimpleCov result formatters. Built-in formatters live
  # below this module; custom formatters should respond to `#format(result)`
  # and can be wired up via `SimpleCov.formatter=`.
  # TODO: Documentation on how to build your own formatters
  module Formatter
    # Formatters can be configured either as classes (instantiated
    # fresh for every report) or as ready-built instances — the only
    # way to reach constructor options like
    # `HTMLFormatter.new(silent: true)`. See #1240.
    def self.instance_for(formatter)
      instantiable?(formatter) ? formatter.new : formatter
    end

    # Whether the configured formatter is a class waiting to be
    # instantiated rather than an instance already built.
    #
    # `Class` cannot itself be subclassed, so no object is an instance
    # of a subclass of it, and `instance_of?(Class)` answers for every
    # object exactly as `is_a?(Class)` does. That narrowing is a
    # difference no example can show, which is why it is disabled here
    # rather than pinned by a test.
    # mutant:disable
    def self.instantiable?(formatter)
      formatter.is_a?(Class)
    end
    private_class_method :instantiable?

    # Normalize a class or instance, then dispatch the result to it.
    def self.format(formatter, result)
      instance_for(formatter).format(result)
    end
  end
end

require_relative "formatter/simple_formatter"
require_relative "formatter/multi_formatter"
require_relative "formatter/json_formatter"
require_relative "formatter/baseline_formatter"
