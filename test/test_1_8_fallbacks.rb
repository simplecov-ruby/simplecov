require 'helper'

# Tests that verify that on 1.8 versions of ruby, simplecov simply
# does not launch and does not cause errors on the way
#
# TODO: This should be expanded upon all methods that could potentially
# be called in a test/spec-helper simplecov config block
#
class Test18FallBacks < Test::Unit::TestCase
  on_ruby '1.8' do
    should "return false when calling SimpleCov.start" do
      assert_equal false, SimpleCov.start
    end

    should "return false when calling SimpleCov.start with a block" do
      assert_equal false, SimpleCov.start { raise "Shouldn't reach this!?" }
    end

    should "return false when calling SimpleCov.configure with a block" do
      assert_equal false, SimpleCov.configure { raise "Shouldn't reach this!?" }
    end

    should "allow to define an adapter" do
      begin
        SimpleCov.adapters.define 'testadapter' do
          add_filter '/config/'
        end
      rescue => err
        assert false, "Adapter definition should have been fine, but raised #{err}"
      end
    end
  end
end
