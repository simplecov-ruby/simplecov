# frozen_string_literal: true

module SimpleCov
  # Namespace for SimpleCov result formatters. Built-in formatters live
  # below this module; custom formatters should respond to `#format(result)`
  # and can be wired up via `SimpleCov.formatter=`.
  # TODO: Documentation on how to build your own formatters
  module Formatter
  end
end

require_relative "formatter/simple_formatter"
require_relative "formatter/multi_formatter"
require_relative "formatter/json_formatter"
