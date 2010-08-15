require 'helper'

class TestMergeHelpers < Test::Unit::TestCase
  context "With two faked coverage resultsets" do
    setup do
      @resultset1 = {source_fixture('sample.rb') => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil],
          source_fixture('app/models/user.rb') => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil],
          source_fixture('app/controllers/sample_controller.rb') => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil]}
          
      @resultset2 = {source_fixture('sample.rb') => [1, nil, 1, 1, nil, nil, 1, 1, nil, nil],
          source_fixture('app/models/user.rb') => [nil, 1, 5, 1, nil, nil, 1, 0, nil, nil],
          source_fixture('app/controllers/sample_controller.rb') => [nil, 3, 1, nil, nil, nil, 1, 0, nil, nil]}
    end
    
    context "a merge" do
      setup do
        assert @merged = @resultset1.merge_resultset(@resultset2)
      end
      
      should "have proper results for sample.rb" do
        assert_equal [1, 1, 2, 2, nil, nil, 2, 2, nil, nil], @merged[source_fixture('sample.rb')]
      end
      
      should "have proper results for user.rb" do
        assert_equal [nil, 2, 6, 2, nil, nil, 2, 0, nil, nil], @merged[source_fixture('app/models/user.rb')]
      end
      
      should "have proper results for sample_controller.rb" do
        assert_equal [nil, 4, 2, 1, nil, nil, 2, 0, nil, nil], @merged[source_fixture('app/controllers/sample_controller.rb')]
      end
    end
  end
end