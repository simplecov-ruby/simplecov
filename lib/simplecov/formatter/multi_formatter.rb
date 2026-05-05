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
            warn("Formatter #{formatter} failed with #{e.class}: #{e.message} (#{e.backtrace.first})")
            nil
          end
        end
      end

      def self.new(formatters = nil)
        Class.new do
          define_method :formatters do
            @formatters ||= Array(formatters)
          end
          include InstanceMethods
        end
      end

      def self.[](*args)
        warn "#{Kernel.caller.first}: [DEPRECATION] ::[] is deprecated. Use ::new instead."
        new(Array(args))
      end
    end
  end
end
