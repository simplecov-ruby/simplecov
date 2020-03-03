require 'bundler/setup'
require 'simplecov'
SimpleCov.enable_for_subprocesses = true
SimpleCov.at_fork.call(Process.pid)
SimpleCov.start
