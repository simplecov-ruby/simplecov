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

# Taken from http://stackoverflow.com/questions/4459330/how-do-i-temporarily-redirect-stderr-in-ruby
require "stringio"

def capture_stderr
  # The output stream must be an IO-like object. In this case we capture it in
  # an in-memory IO object so we can return the string value. You can assign any
  # IO object here.
  previous_stderr, $stderr = $stderr, StringIO.new
  yield
  $stderr.string
ensure
  # Restore the previous value of stderr (typically equal to STDERR).
  $stderr = previous_stderr
end
