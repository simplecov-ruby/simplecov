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
  
  # Keep 1.8-rubies from complaining about missing tests in each file that covers only 1.9 functionality
  def default_test
  end
end

require 'shoulda_macros'
Test::Unit::TestCase.send :extend, ShouldaMacros