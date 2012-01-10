unless RUBY_VERSION =~ /1\.9/
  $stderr.puts "Sorry, Cucumber features are only meant to run on Ruby 1.9 for now :("
  exit 0
end

require 'bundler'
Bundler.setup
require 'aruba/cucumber'
require 'capybara/cucumber'

# Fake rack app for capybara that just returns the latest coverage report from aruba temp project dir
Capybara.app = lambda {|env|
  [200, {'Content-Type' => 'text/html'},
    [File.read(File.join(File.dirname(__FILE__), '../../tmp/aruba/project', 'coverage/index.html'))]]
}

Before do
  @aruba_timeout_seconds = 20
  this_dir = File.dirname(__FILE__)
  # Clean up and create blank state for fake project
  in_current_dir do
    FileUtils.rm_rf 'project'
    FileUtils.cp_r File.join(this_dir, '../../test/faked_project/'), 'project'
  end
  step 'I cd to "project"'
end
