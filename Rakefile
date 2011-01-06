require 'bundler'
Bundler::GemHelper.install_tasks

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/test_*.rb'
  test.verbose = true
end

task :default => :test

require 'rake/rdoctask'
Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "simplecov #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end

TestedRubyVersions = %w(1.9.2 1.8.7 1.8.6)

desc "Perorms bundle install on all rvm-tested ruby versions (#{TestedRubyVersions.join(', ')})"
task :"multitest:bundle" do
  system "rvm #{TestedRubyVersions.join(',')} exec bundle install"
end

desc "Runs tests using rvm for: #{TestedRubyVersions.join(', ')}"
task :multitest do
  system "rvm #{TestedRubyVersions.join(',')} rake test"
end

