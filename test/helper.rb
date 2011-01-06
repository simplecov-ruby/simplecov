require 'rubygems'
require 'bundler/setup'
require 'simplecov'

require 'test/unit'
require 'shoulda'

SimpleCov.coverage_dir('tmp/coverage')

class Test::Unit::TestCase
  def source_fixture(filename)
    File.expand_path(File.join(File.dirname(__FILE__), 'fixtures', filename))
  end
end