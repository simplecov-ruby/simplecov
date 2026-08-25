require_relative "boot"

require "logger"
require "rails"
# Only the frameworks the view specs need. The demo has no database, no
# jobs, and no mailers: it exists to render templates.
require "action_controller/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module ViewDemo
  class Application < Rails::Application
    config.load_defaults 7.2
  end
end
