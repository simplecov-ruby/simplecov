# frozen_string_literal: true

require "test_helper"
require "faked_project/some_class"

class SomeTest < Minitest::Test
  def setup
    @instance = SomeClass.new("foo")
  end

  def test_reverse
    assert_equal "oof", @instance.reverse
  end

  def test_comparison
    assert @instance.compare_with("foo")
  end
end
