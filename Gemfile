# frozen_string_literal: true

source "https://rubygems.org"

# Uncomment this to use local copy of simplecov-html in development when checked out
# gem "simplecov-html", path: File.join(__dir__, "../simplecov-html")

# Uncomment this to use development version of html formatter from github
# gem "simplecov-html", github: "simplecov-ruby/simplecov-html"

# Since simplecov-html has not had a release recently and we need the updated gem for rack to address a
# security finding, forcing simplecov to use this version where rack was updated.
gem "simplecov-html", github: "simplecov-ruby/simplecov-html", ref: '663e3fe'

gem "matrix"

group :development do
  gem "apparition", github: "twalpole/apparition" # LOCKED: When this is released, use a released version https://github.com/twalpole/apparition/pull/79
  gem "aruba", "~> 1.0"
  gem "capybara", "~> 3.31"
  gem "rackup"
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
