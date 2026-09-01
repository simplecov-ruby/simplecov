# frozen_string_literal: true

module SimpleCov
  module Formatter
    class MultiFormatter
      module InstanceMethods
        def format(result)
          formatters.map do |formatter|
            Formatter.format(formatter, result)
          rescue => e
            warn("Formatter #{formatter} failed with #{e.class}: #{e} (#{(_ = e.backtrace).first})")
          end
        end
      end

      # Normalized eagerly and captured in the closure. `Array()` is pure for every
      # accepted input shape, so this is equivalent to the historical lazy
      # per-instance memoization.
      def self.new(formatters = nil)
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
