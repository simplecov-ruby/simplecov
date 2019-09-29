$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), "..", "..", ".."))
require "lib/simplecov"
if ENV.key? "PRINT_ERROR_STATUS"
  SimpleCov.print_error_status = ENV["PRINT_ERROR_STATUS"] == "true"
end
SimpleCov.start
require "test/unit"
class FooTest < Test::Unit::TestCase
  def test_foo
    assert false
  end
end
