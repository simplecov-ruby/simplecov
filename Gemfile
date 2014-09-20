source 'https://rubygems.org'

# Uncomment this to use local copy of simplecov-html in development when checked out
# gem 'simplecov-html', :path => ::File.dirname(__FILE__) + '/../simplecov-html'

# Uncomment this to use development version of html formatter from github
# gem 'simplecov-html', :github => 'colszowka/simplecov-html'

gemspec

gem 'rake', '>= 10.3'

group :test do
  gem 'activesupport', '~> 3.2.0' # Older version required for Ruby 1.8.7 support
  gem 'rspec', '>= 3.0'
  gem 'rspec-legacy_formatters', '>= 1.0'
  gem 'shoulda', '>= 3.5'
  gem 'shoulda-matchers', '~> 2.0.0' # Older version required for Ruby 1.8.7 support
end

if 'Integration test (cucumber) suite is 1.9+ only'.respond_to?(:encoding)
  gem 'aruba', '~> 0.6'
  gem 'capybara', '~> 2.0.0'
  gem 'poltergeist', '~> 1.1'
  gem 'phantomjs', '~> 1.9'
  gem 'cucumber', '~> 1.1'
end
