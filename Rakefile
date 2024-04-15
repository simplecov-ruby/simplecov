# frozen_string_literal: true

require "rubygems"
require "bundler/setup"
Bundler::GemHelper.install_tasks

# See https://github.com/simplecov-ruby/simplecov/issues/171
desc "Set permissions on all files so they are compatible with both user-local and system-wide installs"
task :fix_permissions do
  system 'bash -c "find lib/ -type f -exec chmod 644 {} \; && find . -type d -exec chmod 755 {} \;"'
end
# Enforce proper permissions on each build
Rake::Task[:build].prerequisites.unshift :fix_permissions

require "rspec/core/rake_task"
RSpec::Core::RakeTask.new(:spec)

begin
  require "rubocop/rake_task"
  RuboCop::RakeTask.new
rescue LoadError
  task :rubocop do
    warn "Rubocop is disabled"
  end
end

require "cucumber/rake/task"
Cucumber::Rake::Task.new do |t|
  t.cucumber_opts = %w[--retry 3 --no-strict-flaky]
end

task test: %i[spec cucumber]
task default: %i[rubocop spec cucumber]
