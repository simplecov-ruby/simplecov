# frozen_string_literal: true

require_relative "formatter/html_formatter"
module SimpleCov
  module Formatter
    class << self
      def from_env(env)
        formatters = [SimpleCov::Formatter::HTMLFormatter]

        # When running under a CI that uses CodeClimate, JSON output is expected
        formatters.push(SimpleCov::Formatter::JSONFormatter) if env.fetch("CC_TEST_REPORTER_ID", nil)

        formatters
      end
    end
  end
end
