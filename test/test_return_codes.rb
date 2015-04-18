require "helper"

# Make sure that exit codes of tests are propagated properly when using
# simplecov. See github issue #5
class TestReturnCodes < Minitest::Test
  def self.test_order
    :alpha
  end

  context "Inside fixtures/frameworks" do
    setup do
      @current_dir = Dir.getwd
      Dir.chdir(File.join(File.dirname(__FILE__), "fixtures", "frameworks"))
      FileUtils.rm_rf("./coverage")
    end

    should "have return code 0 when running testunit_good.rb" do
      `ruby testunit_good.rb`
      assert_equal 0, $?.exitstatus
    end

    should "have return code 0 when running rspec_good.rb" do
      `rspec rspec_good.rb`
      assert_equal 0, $?.exitstatus
    end

    should "have non-0 return code when running testunit_bad.rb" do
      `ruby testunit_bad.rb`
      refute_equal 0, $?.exitstatus
    end

    should "have return code 1 when running rspec_bad.rb" do
      `rspec rspec_bad.rb`
      refute_equal 0, $?.exitstatus
    end

    teardown do
      Dir.chdir(@current_dir)
    end
  end
end
