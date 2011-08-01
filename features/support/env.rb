require 'rubygems'
require 'bundler'
Bundler.setup
require 'aruba'

unless RUBY_VERSION =~ /1\.9/
  puts "Sorry, Cucumber features are only meant to run on Ruby 1.9 for now :("
  exit 0
end

Before do
  this_dir = File.dirname(__FILE__)
  in_current_dir do
    FileUtils.cp_r File.join(this_dir, '../../test/faked_project/'), 'project'
  end
end

if RUBY_VERSION > '1.9.1'
  Before do
    set_env('RUBYOPT', '-I.:../../lib')
  end
elsif RUBY_PLATFORM == 'java'
  Before do
    set_env('RUBYOPT', '-I../../lib -rubygems')
  end
end