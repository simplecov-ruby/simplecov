require 'rubygems'
require 'bundler'
Bundler.setup(:default, :development)
require 'test/unit'
require 'shoulda'

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'simplecov'
SimpleCov.coverage_dir('tmp/coverage')

class Test::Unit::TestCase
  def source_fixture(filename)
    File.expand_path(File.join(File.dirname(__FILE__), 'fixtures', filename))
  end
end
