# frozen_string_literal: true

source "https://rubygems.org"

# Uncomment this to use local copy of simplecov-html in development when checked out
# gem "simplecov-html", path: File.join(__dir__, "../simplecov-html")

# Uncomment this to use development version of html formatter from github
# gem "simplecov-html", github: "simplecov-ruby/simplecov-html"

gem "matrix"

group :development do
  gem "apparition", github: "twalpole/apparition"
  gem "activesupport", "~> 6.1"
  gem "aruba"
  gem "capybara"
  gem "rackup"
  gem "cucumber"
  gem "minitest"
  gem "rake"
  gem "rspec"
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
