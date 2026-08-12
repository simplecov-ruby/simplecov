# frozen_string_literal: true

Rails.application.configure do
  config.eager_load = false
  config.consider_all_requests_local = true
  config.action_controller.allow_forgery_protection = false
  config.active_support.deprecation = :stderr
end
