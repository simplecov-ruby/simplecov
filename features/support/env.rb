# frozen_string_literal: true

# While you're here, handy tip for debugging: try to attach @announce-output
# @announce-command to the scenarios/features to see what's going on

require "bundler"
Bundler.setup
# require order matters, capybara needs to be there before aruba for the RSpec shadowing fix to work (see slightly below)
require "capybara/cucumber"
require "capybara/apparition"
require "aruba/cucumber"
require "aruba/config/jruby" if RUBY_ENGINE == "jruby"
require "simplecov"

# Small workaround I found for the RSpec/aruba shadowing problem showcased in https://github.com/PragTob/all_conflict/
# It _seems_ to work for now but it's definitely not ideal. Wish this was fixed in Capybara.
Aruba::Api::Core.include(Capybara::RSpecMatcherProxies)

# Rack app for Capybara which returns the latest coverage report from Aruba temp project dir
coverage_dir = File.expand_path("../../tmp/aruba/project/coverage/", __dir__)
Capybara.app = Rack::Builder.new do
  use Rack::Static, urls: {"/" => "index.html"}, root: coverage_dir
  run Rack::Directory.new(coverage_dir)
end.to_app

Capybara.configure do |config|
  config.ignore_hidden_elements = false
  config.server = :webrick
  config.default_driver = :apparition
end

Before("@branch_coverage") do
  skip_this_scenario unless SimpleCov.branch_coverage_supported?
end

Before("@rails6") do
  # Rails 6 only supports Ruby 2.5+
  skip_this_scenario if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("2.5")
end

Before("@process_fork") do
  # Process.fork is NotImplementedError in jruby
  skip_this_scenario if jruby?
end

Before("@no_jruby") do
  skip_this_scenario if jruby?
end

def jruby?
  defined?(RUBY_ENGINE) && RUBY_ENGINE == "jruby"
end

Aruba.configure do |config|
  config.allow_absolute_paths = true

  # JRuby needs a bit longer to get going
  config.exit_timeout = RUBY_ENGINE == "jruby" ? 60 : 20
end
