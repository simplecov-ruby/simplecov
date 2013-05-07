source "https://rubygems.org"
source "http://gems.ooyala.com"
gemspec

if 'Integration test (cucumber) suite is 1.9+ only'.respond_to? :encoding
  gem 'aruba', '~> 0.5.1'
  gem 'capybara', '~> 2.0'
  gem 'poltergeist', '~> 1.1.0'
  gem 'phantomjs', '~> 1.8.1'
  gem 'cucumber', '>= 1.1.0'
  gem "ooyala-grit"
  gem "pry-nav"
  gem "algorithms"
  gem "simplecov-html", '=0.7.1.ooyala'
end

# Uncomment this to use local copy of simplecov-html in development when checked out
# gem 'simplecov-html', :path => ::File.dirname(__FILE__) + '/../simplecov-html'
# gem 'simplecov-html', :path => "/Users/rkonda/repos/simplecov-html"

# Uncomment this to use development version of html formatter from github
# gem 'simplecov-html', :github => 'colszowka/simplecov-html'
