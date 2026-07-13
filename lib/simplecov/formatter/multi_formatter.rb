# frozen_string_literal: true

module SimpleCov
  module Formatter
    # Wraps multiple formatters so SimpleCov.formatter can drive several
    # output formats (HTML + JSON, etc.) in a single run.
    class MultiFormatter
      # Shared `#format` implementation; included into individual
      # MultiFormatter subclasses built by `MultiFormatter.new`.
      module InstanceMethods
        def format(result)
          formatters.map do |formatter|
            formatter.new.format(result)
          rescue StandardError => e
            warn("Formatter #{formatter} failed with #{e.class}: #{e.message} (#{(_ = e.backtrace).first})")
            nil
          end
        end
      end

      def self.new(formatters = nil)
        # Normalize eagerly and capture the list in the closure. Array()
        # is pure for every accepted input shape (nil, single formatter,
        # array, or another MultiFormatter class), so this is equivalent
        # to the historical lazy per-instance memoization.
        formatter_list = Array(formatters)
        Class.new do
          define_method :formatters do
            formatter_list
          end
          include InstanceMethods
        end
      end
    end
  end
end
