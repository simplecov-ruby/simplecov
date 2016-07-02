source "https://rubygems.org"

# Uncomment this to use local copy of simplecov-html in development when checked out
# gem 'simplecov-html', :path => ::File.dirname(__FILE__) + '/../simplecov-html'

# Uncomment this to use development version of html formatter from github
# gem 'simplecov-html', :github => 'colszowka/simplecov-html'

gem "rake", Gem::Version.new(RUBY_VERSION) < Gem::Version.new("1.9.3") ? "~>10.3" : ">= 10.3"

group :test do
  gem "rspec", ">= 3.2"
  # Older versions of some gems required for Ruby 1.8.7 support
  platform :ruby_18 do
    gem "activesupport", "~> 3.2.21"
    gem "i18n", "~> 0.6.11"
  end
  platform :ruby_18, :ruby_19 do
    gem "json", "~> 1.8"
  end
  platform :ruby_18, :ruby_19, :ruby_20, :ruby_21 do
    gem "rack", "~> 1.6"
  end
  gem "aruba"
  gem "capybara"
  gem "cucumber"
  gem "phantomjs"
  gem "poltergeist"
  gem "rubocop", "~> 0.41.0"
  gem "test-unit"
end

gemspec
