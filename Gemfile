source "http://rubygems.org"
gemspec

# Use local copy of simplecov-html in development when checked out
if File.directory?('../simplecov-html')
  gem 'simplecov-html', :path => '../simplecov-html'
else
  gem 'simplecov-html', :git => 'https://github.com/colszowka/simplecov-html'
end