# frozen_string_literal: true

source "https://rubygems.org"

# Uncomment this to use local copy of simplecov-html in development when checked out
# gem "simplecov-html", path: File.dirname(__FILE__) + "/../simplecov-html"

# Uncomment this to use development version of html formatter from github
# gem "simplecov-html", github: "simplecov-ruby/simplecov-html"

gem "matrix"

group :development do
  # Waiting for a release of the gem, see https://github.com/twalpole/apparition/pull/79
  gem "apparition", github: "twalpole/apparition", ref: "ca86be4d54af835d531dbcd2b86e7b2c77f85f34"
  gem "aruba", "~> 1.0"
  gem "capybara", "~> 3.31"
  gem "cucumber", "~> 4.0"
  gem "minitest"
  gem "rake", "~> 13.0"
  gem "rspec", "~> 3.2"
  gem "pry"
  gem "rubocop"
  gem "test-unit"
  # Explicitly add webrick because it has been removed from stdlib in Ruby 3.0
  gem "webrick"
end

group :benchmark do
  gem "benchmark-ips"
end

gemspec
