require "bundler/setup"
require "simplecov"
require "minitest/autorun"
require "shoulda"

SimpleCov.coverage_dir("tmp/coverage")

def source_fixture(filename)
  File.expand_path(File.join(File.dirname(__FILE__), "fixtures", filename))
end

require "shoulda_macros"
Minitest::Test.send :extend, ShouldaMacros

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
