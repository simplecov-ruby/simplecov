# encoding: utf-8
$:.push File.expand_path('../lib', __FILE__)
require 'simplecov/version'

Gem::Specification.new do |gem|
  gem.name        = 'simplecov'
  gem.version     = SimpleCov::VERSION
  gem.platform    = Gem::Platform::RUBY
  gem.authors     = ["Christoph Olszowka"]
  gem.email       = ['christoph at olszowka de']
  gem.homepage    = 'http://github.com/colszowka/simplecov'
  gem.description = %Q{Code coverage for Ruby 1.9+ with a powerful configuration library and automatic merging of coverage across test suites}
  gem.summary     = gem.description
  gem.license     = "MIT"

  gem.add_dependency 'multi_json', '~> 1.0'
  gem.add_dependency 'simplecov-html', '~> 0.8.0'
  gem.add_dependency 'docile', '~> 1.1.0'

  gem.files         = `git ls-files`.split("\n")
  gem.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  gem.require_paths = ['lib']
end
