require "spec_helper"
ENV["RAILS_ENV"] ||= "test"

require_relative "../config/environment"

require "rspec/rails"

RSpec.configure do |config|
  # Specs under spec/views render templates directly, without a
  # controller or a route.
  config.infer_spec_type_from_file_location!
end
