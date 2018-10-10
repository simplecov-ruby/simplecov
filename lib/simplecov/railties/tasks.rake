# frozen_string_literal: true

require "rake/testtask"
Rake::TestTask.new do |t|
  t.name = "simplecov"
  t.loader = :direct
  t.libs.push "test", "spec", Dir.pwd
  t.test_files = FileList["{test,spec}/**/*_{test,spec}.rb"]
  t.ruby_opts.push "-r", "simplecov", "-e", "SimpleCov.start(:rails)".inspect
end

require "rake/clean"
CLOBBER.include "coverage"
