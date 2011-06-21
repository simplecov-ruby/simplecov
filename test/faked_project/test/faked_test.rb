require 'test_helper'

class FakedTest < Test::Unit::TestCase
  def test_something
    assert_equal 'bar', FakedProject.foo
  end
end