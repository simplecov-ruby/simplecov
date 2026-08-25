Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  config.cache_classes = true

  # Do not eager load code on boot: the view specs autoload the two model
  # classes they touch, and nothing else needs loading.
  config.eager_load = false

  # Show full error reports and disable caching.
  config.consider_all_requests_local       = true
  config.action_controller.perform_caching = false
  config.cache_store = :null_store

  # Raise exceptions instead of rendering exception templates.
  config.action_dispatch.show_exceptions = :none

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr
end
