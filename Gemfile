# frozen_string_literal: true

source "https://rubygems.org"

case ENV.fetch("SIMPLECOV_HTML_MODE", nil)
when "local"
  # Use local copy of simplecov-html in development when checked out
  gem "simplecov-html", path: File.join(__dir__, "../simplecov-html")
when "github"
  # Use development version of html formatter from github
  gem "simplecov-html", git: "https://github.com/simplecov-ruby/simplecov-html.git"
when "methods" # TODO: remove after simplecov-html release
  gem "simplecov-html", git: "https://github.com/umbrellio/simplecov-html.git", branch: "add-method-coverage-support"
end

gem "base64"
gem "bigdecimal"
gem "matrix"
gem "mutex_m"
gem "ostruct"

group :development do
  gem "apparition", git: "https://github.com/twalpole/apparition.git"
  gem "activesupport", "~> 6.1"
  gem "aruba"
  gem "capybara"
  if RUBY_VERSION < "2.7"
    gem "rack", "< 3"
  else
    gem "rackup"
  end
  gem "cucumber"
  gem "minitest"
  gem "rake"
  gem "rspec"
  gem "pry"
  gem "rubocop", "~> 1.70.0" if RUBY_VERSION > "3.2"
  gem "test-unit"
  gem "logger"
  gem "power_assert", "~> 2.0" if RUBY_VERSION < "3.0"
  # Explicitly add webrick because it has been removed from stdlib in Ruby 3.0
  gem "webrick"
end

group :benchmark do
  gem "benchmark-ips"
end

gemspec
