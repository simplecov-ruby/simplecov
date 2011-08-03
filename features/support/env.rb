unless RUBY_VERSION =~ /1\.9/
  $stderr.puts "Sorry, Cucumber features are only meant to run on Ruby 1.9 for now :("
  exit 0
end

require 'rubygems'
require 'bundler'
Bundler.setup
require 'aruba/cucumber'
require 'capybara/cucumber'

Capybara.app = lambda {|env| 
  [200, {'Content-Type' => 'text/html'}, 
    [File.read(File.join(File.dirname(__FILE__), '../../tmp/aruba/project', 'coverage/index.html'))]]
}

Before do
  @aruba_timeout_seconds = 7
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