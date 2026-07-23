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
      formatter.is_a?(Class) ? formatter.new : formatter
    end
  end
end

require_relative "formatter/simple_formatter"
require_relative "formatter/multi_formatter"
require_relative "formatter/json_formatter"
