# frozen_string_literal: true

module Minitest
  def self.plugin_simplecov_init(_options)
    Minitest.after_run do
      SimpleCov.custom_at_exit if SimpleCov.respond_to?(:custom_at_exit)
    end
  end
end
