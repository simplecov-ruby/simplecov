#!/usr/bin/env rake

require "rubygems"
require "bundler/setup"
Bundler::GemHelper.install_tasks

# See https://github.com/colszowka/simplecov/issues/171
desc "Set permissions on all files so they are compatible with both user-local and system-wide installs"
task :fix_permissions do
  system 'bash -c "find . -type f -exec chmod 644 {} \; && find . -type d -exec chmod 755 {} \;"'
end
# Enforce proper permissions on each build
Rake::Task[:build].prerequisites.unshift :fix_permissions

require "rake/testtask"
Rake::TestTask.new(:test) do |test|
  test.libs << "lib" << "test"
  test.test_files = FileList["test/test_*.rb"]
  test.verbose = true
  test.warning = true
end

begin
  require "rubocop/rake_task"
  RuboCop::RakeTask.new
rescue LoadError
  task :rubocop do
    $stderr.puts "Rubocop is disabled"
  end
end

# Cucumber integration test suite is for impls that work with simplecov only - a.k.a. 1.9+
if RUBY_VERSION >= "1.9"
  require "cucumber/rake/task"
  Cucumber::Rake::Task.new
  task :default => [:test, :cucumber, :rubocop]
else
  task :default => [:test]
end
