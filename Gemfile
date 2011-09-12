source "http://rubygems.org"
gemspec

# Use local copy of simplecov-html in development when checked out
if File.directory?(File.dirname(__FILE__) + '/../simplecov-html')
  gem 'simplecov-html', :path => File.dirname(__FILE__) + '/../simplecov-html'
else
  gem 'simplecov-html', :git => 'https://github.com/colszowka/simplecov-html'
end
