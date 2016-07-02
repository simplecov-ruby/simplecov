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
    gem "addressable", "~> 2.3.8"
    gem "gherkin", "~> 2.12.2"
    gem "i18n", "~> 0.6.11"
    gem "mime-types", "~> 1.25"
  end
  platform :ruby_18, :ruby_19 do
    gem "json", "~> 1.8"
  end
  platform :ruby_19 do
    gem "mime-types", "~> 2.0"
  end
  platform :ruby_18, :ruby_19, :ruby_20, :ruby_21 do
    gem "rack", "~> 1.6"
  end
  platform :jruby, :ruby_19, :ruby_20, :ruby_21, :ruby_22, :ruby_23 do
    gem "rubocop", "~> 0.41.0"
  end
  gem "aruba", "~> 0.7.4"
  gem "capybara"
  gem "cucumber"
  gem "phantomjs", "~> 1.9"
  gem "poltergeist"
  gem "test-unit"
end

gemspec
