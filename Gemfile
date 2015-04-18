source "https://rubygems.org"

# Uncomment this to use local copy of simplecov-html in development when checked out
# gem 'simplecov-html', :path => ::File.dirname(__FILE__) + '/../simplecov-html'

# Uncomment this to use development version of html formatter from github
# gem 'simplecov-html', :github => 'colszowka/simplecov-html'

gem "rake", ">= 10.3"

group :test do
  # Older versions of some gems required for Ruby 1.8.7 support
  platform :ruby_18 do
    gem "activesupport", "~> 3.2.21"
    gem "shoulda-matchers", "~> 2.0.0"
    gem "i18n", "~> 0.6.11"
  end
  gem "rubocop", ">= 0.30", :platforms => [:ruby_19, :ruby_20, :ruby_21, :ruby_22]
  gem "minitest", ">= 5.5"
  gem "rspec", ">= 3.0"
  gem "rspec-legacy_formatters", ">= 1.0"
  gem "shoulda", ">= 3.5"
end

platform :jruby, :ruby_19, :ruby_20, :ruby_21, :ruby_22 do
  gem "aruba", "~> 0.6"
  gem "capybara", "~> 2.0.0"
  gem "cucumber", "~> 2.0"
  gem "phantomjs", "~> 1.9"
  gem "poltergeist", "~> 1.1"
  gem "test-unit", "~> 3.0"
end

gemspec
