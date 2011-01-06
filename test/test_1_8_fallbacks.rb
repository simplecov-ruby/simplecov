require 'helper'

# Tests that verify that on 1.8 versions of ruby, simplecov simply
# does not launch and does not cause errors on the way
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
  end
end
