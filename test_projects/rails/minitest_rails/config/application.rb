# frozen_string_literal: true

require_relative "boot"

require "logger"
require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

module MinitestRails
  class Application < Rails::Application
    config.load_defaults 8.1
  end
end
