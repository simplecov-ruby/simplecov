require 'bundler/setup'
require 'simplecov'
SimpleCov.command_name 'spawn'
SimpleCov.at_fork.call(Process.pid)
SimpleCov.start
