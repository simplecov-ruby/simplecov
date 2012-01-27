#!/usr/bin/env rake

require 'bundler'
Bundler::GemHelper.install_tasks

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.test_files = FileList['test/test_*.rb']
  test.verbose = true
end

require 'cucumber/rake/task'
Cucumber::Rake::Task.new

task :default => [:test, :cucumber]
