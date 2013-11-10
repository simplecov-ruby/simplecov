source "https://rubygems.org"
gemspec

if 'Integration test (cucumber) suite is 1.9+ only'.respond_to? :encoding
  gem 'aruba', '~> 0.5.1'
  gem 'capybara', '~> 2.0'
  gem 'poltergeist', '~> 1.1.0'
  gem 'phantomjs', '~> 1.8.1'
  gem 'cucumber', '>= 1.1.0'
end

# shoulda-matchers depends on rails >= 4, but that does not work with Ruby < 1.9. So, to allow CI builds on those versions,
# we gotta stick with the 3.x line.
gem 'activesupport', '~> 3.2.0'

# Uncomment this to use local copy of simplecov-html in development when checked out
# gem 'simplecov-html', :path => ::File.dirname(__FILE__) + '/../simplecov-html'

# Uncomment this to use development version of html formatter from github
# gem 'simplecov-html', :github => 'colszowka/simplecov-html'
