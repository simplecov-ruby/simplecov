# frozen_string_literal: true

source "https://rubygems.org"

group :development do
  gem "json_schemer"
  gem "rake"
  gem "rspec"
  gem "test-unit"

  # The cucumber feature suite and its browser-driven HTML report tests run
  # only on MRI; JRuby runs `rake spec` only, so skip the whole stack there.
  # This also keeps rdoc 8 (and its rbs dependency, whose native extension
  # fails to build on JRuby) out of the resolution, since aruba pulls it in
  # transitively via irb. The Rakefile guards `require "cucumber/rake/task"`
  # with a matching rescue so `rake spec` still loads without these gems.
  unless RUBY_ENGINE == "jruby"
    gem "aruba", ">= 2.0"
    gem "capybara"
    gem "cucumber"
    gem "cuprite"
    gem "nokogiri"
    gem "rackup"
    gem "rbs", ">= 4.0"
    gem "steep", ">= 1.10", require: false
    # Explicitly add webrick because it has been removed from stdlib in Ruby 3.0
    gem "webrick"
  end

  if RUBY_VERSION > "3.2"
    gem "rubocop"
    gem "rubocop-capybara"
    gem "rubocop-performance"
    gem "rubocop-rake"
    gem "rubocop-rspec"
  end
end

group :benchmark do
  gem "benchmark-ips"
end

gemspec
