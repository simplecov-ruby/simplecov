# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "simplecov/version"

Gem::Specification.new do |s|
  s.name        = "simplecov"
  s.version     = SimpleCov::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Christoph Olszowka"]
  s.email       = ["christoph at olszowka de"]
  s.homepage    = "http://github.com/colszowka/simplecov"
  s.summary     = %Q{Code coverage for Ruby 1.9 with a powerful configuration library and automatic merging of coverage across test suites}
  s.description = %Q{Code coverage for Ruby 1.9 with a powerful configuration library and automatic merging of coverage across test suites}

  s.rubyforge_project = "simplecov"
  
  s.add_dependency 'simplecov-html', "~> 0.4.4"
  s.add_development_dependency "shoulda", "2.10.3"
  s.add_development_dependency "rspec", "~> 2.0.0"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end