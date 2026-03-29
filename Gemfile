# frozen_string_literal: true

source "https://rubygems.org"

# Uncomment this to use local copy of simplecov-html in development when checked out
# gem "simplecov-html", path: File.join(__dir__, "../simplecov-html")

# Uncomment this to use development version of html formatter from github
# gem "simplecov-html", github: "simplecov-ruby/simplecov-html"

group :development do
  gem "cuprite"
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
  gem "rubocop" if RUBY_VERSION > "3.2"
  gem "test-unit"
  # Explicitly add webrick because it has been removed from stdlib in Ruby 3.0
  gem "webrick"
end

group :benchmark do
  gem "benchmark-ips"
end

gemspec
