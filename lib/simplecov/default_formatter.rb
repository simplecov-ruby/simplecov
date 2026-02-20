# frozen_string_literal: true

require "simplecov-html"
module SimpleCov
  module Formatter
    class << self
      def from_env(env)
        formatters = [SimpleCov::Formatter::HTMLFormatter]

        # When running under a CI that uses Qlty, JSON output is expected
        # 
        # CC_TEST_REPORTER_ID is the previous environment variable which was used by
        # Code Climate's test reporter. QLTY_COVERAGE_TOKEN is the new environment
        # variable used by Qlty.
        # 
        # We retain detection of CC_TEST_REPORTER_ID for backwards compatibility.
        if env.fetch("CC_TEST_REPORTER_ID", nil) || env.fetch("QLTY_COVERAGE_TOKEN", nil)
          require "simplecov_json_formatter"
          formatters.push(SimpleCov::Formatter::JSONFormatter)
        end

        formatters
      end
    end
  end
end
