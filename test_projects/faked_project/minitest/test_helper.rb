# frozen_string_literal: true

require "bundler/setup"

# We're injecting simplecov_config via aruba in cucumber here
# depending on what the test case is...
begin
  require File.join(File.dirname(__FILE__), "simplecov_config")
rescue LoadError
  warn "No SimpleCov config file found!"
end

require "minitest/autorun"
