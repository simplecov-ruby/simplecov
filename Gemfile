# frozen_string_literal: true

source "https://rubygems.org"

group :development do
  gem "nokogiri"
  gem "cuprite"
  gem "aruba"
  gem "capybara"
  gem "rackup"
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
