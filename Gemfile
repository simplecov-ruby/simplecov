# frozen_string_literal: true

source "https://rubygems.org"

group :development do
  gem "nokogiri"
  gem "cuprite"
  gem "aruba", ">= 2.0"
  gem "capybara"
  gem "rackup"
  gem "cucumber"
  gem "rake"
  gem "rspec"
  if RUBY_VERSION > "3.2"
    gem "rubocop"
    gem "rubocop-capybara"
    gem "rubocop-performance"
    gem "rubocop-rake"
    gem "rubocop-rspec"
  end
  gem "test-unit"
  # Explicitly add webrick because it has been removed from stdlib in Ruby 3.0
  gem "webrick"
end

group :benchmark do
  gem "benchmark-ips"
end

gemspec
