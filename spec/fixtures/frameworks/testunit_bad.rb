$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), "..", "..", ".."))
require "lib/simplecov"
SimpleCov.print_errors ENV["PRINT_ERRORS"] == "true" if ENV.key? "PRINT_ERRORS"
SimpleCov.start
require "test/unit"
class FooTest < Test::Unit::TestCase
  def test_foo
    assert false
  end
end
