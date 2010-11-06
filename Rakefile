require 'rubygems'
require 'rake'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.name = "simplecov"
    gem.summary = %Q{Code coverage for Ruby 1.9 with a powerful configuration library and automatic merging of coverage across test suites}
    gem.description = %Q{Code coverage for Ruby 1.9 with a powerful configuration library and automatic merging of coverage across test suites}
    gem.email = "christoph at olszowka de"
    gem.homepage = "http://github.com/colszowka/simplecov"
    gem.authors = ["Christoph Olszowka"]
    gem.add_dependency 'simplecov-html', ">= 0.3.7"
    gem.add_development_dependency "shoulda", "2.10.3"
    gem.add_development_dependency "rspec", "~> 2.0.0"
    gem.add_development_dependency "jeweler", "1.4.0"
    # gem is a Gem::Specification... see http://www.rubygems.org/read/chapter/20 for additional settings
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler (or a dependency) not available. Install it with: gem install jeweler"
end

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/test_*.rb'
  test.verbose = true
end

task :test => :check_dependencies

task :default => :test

require 'rake/rdoctask'
Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "simplecov #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
