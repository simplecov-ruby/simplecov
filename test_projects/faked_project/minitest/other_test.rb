# frozen_string_literal: true

require "bundler/setup"

begin
  require File.expand_path("simplecov_config", __dir__)
rescue LoadError
  warn "No SimpleCov config file found!"
end

require "minitest/autorun"
require "faked_project/some_class"

class OtherTest < Minitest::Test
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
