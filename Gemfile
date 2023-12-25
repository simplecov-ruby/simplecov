# frozen_string_literal: true

source "https://rubygems.org"

case ENV["SIMPLECOV_HTML_MODE"]
when "local"
  # Use local copy of simplecov-html in development when checked out
  gem "simplecov-html", path: File.join(__dir__, "../simplecov-html")
when "github"
  # Use development version of html formatter from github
  gem "simplecov-html", github: "simplecov-ruby/simplecov-html"
when "methods" # TODO: remove after simplecov-html release
  gem "simplecov-html", github: "umbrellio/simplecov-html", branch: "add-method-coverage-support"
end

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
